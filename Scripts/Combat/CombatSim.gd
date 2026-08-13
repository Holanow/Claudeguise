extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")

## The simulation. Owns every mutation of a CombatUnit and every event emitted.
##
## OWNER: wren. Files under Scripts/Combat/ are wren's. Nobody else edits them.
##
## The contract the rest of the project is built against:
##
##   var state := CombatSim.build(party, encounter, seed)
##   while state.outcome == CombatState.Outcome.UNRESOLVED:
##       CombatSim.step(state)
##
## `step` advances exactly one tick and must be pure with respect to everything
## outside `state`. Same seed plus same inputs, same fight, every time.
##
## `deps` is optional on every entry point and defaults to the real content
## system (SimDeps.new() wires to Balance and Registry). Tests pass their own
## SimDeps and never touch Balance, Registry or a single registered class,
## action or enemy.

## Layout-only fallback spacing for party members past the encounter's spawn
## list. Not a combat number: nothing here affects hp, damage or speed.
const _FALLBACK_SPAWN_SPACING := 32.0

## Builds the starting state: places both sides, derives hp and resources
## through `deps`, and emits FIGHT_START.
static func build(party: Array[PawnData], encounter: Encounter, fight_seed: int, deps: SimDeps = null) -> CombatState:
	if deps == null:
		deps = SimDeps.new()
	var state := CombatState.new(fight_seed)
	var next_id := 0

	for i in party.size():
		var unit := _build_player_unit(next_id, party[i], _party_spawn_position(encounter, i), deps)
		state.units.append(unit)
		next_id += 1

	for spawn in encounter.enemy_spawns:
		var enemy_id: StringName = spawn.get("enemy_id", &"")
		var pos: Vector2 = spawn.get("position", Vector2.ZERO)
		var enemy_def: EnemyDef = deps.enemy_lookup.call(enemy_id)
		var unit := _build_enemy_unit(next_id, enemy_def, enemy_id, pos)
		state.units.append(unit)
		next_id += 1

	state.emit(_event(CG.EventKind.FIGHT_START, 0, -1, -1, &""))
	return state

## Advances one tick. Order within a tick is itself a contract, because
## changing it changes every fight: decide intents for all units from the state
## as it was at the start of the tick, then resolve them in unit id order, then
## tick statuses and cooldowns, then check the outcome.
static func step(state: CombatState, deps: SimDeps = null) -> void:
	if state.outcome != CombatState.Outcome.UNRESOLVED:
		return
	if deps == null:
		deps = SimDeps.new()
	state.tick += 1
	_decide_phase(state, deps)
	_resolve_phase(state, deps)
	_tick_phase(state, deps)
	_check_outcome(state)

## Runs to completion. Used by tests and by the headless balance checks; the
## battle view calls step() itself so it can draw between ticks.
static func run(state: CombatState, deps: SimDeps = null) -> CombatState.Outcome:
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		step(state, deps)
	return state.outcome

# ---------------------------------------------------------------------------
# build() helpers
# ---------------------------------------------------------------------------

static func _party_spawn_position(encounter: Encounter, index: int) -> Vector2:
	if index < encounter.party_spawns.size():
		return encounter.party_spawns[index]
	var base := Vector2.ZERO
	if not encounter.party_spawns.is_empty():
		base = encounter.party_spawns[encounter.party_spawns.size() - 1]
	var overflow := index - encounter.party_spawns.size() + 1
	return base + Vector2(float(overflow) * _FALLBACK_SPAWN_SPACING, 0.0)

static func _build_player_unit(id: int, pawn: PawnData, pos: Vector2, deps: SimDeps) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.PLAYER
	u.display_name = pawn.display_name
	u.pawn = pawn
	u.position = pos
	u.hp_max = int(deps.max_hp.call(pawn))
	u.hp = u.hp_max
	u.resource_max = int(deps.max_resource.call(pawn))
	u.resource = u.resource_max
	u.resource_kind = pawn.pawn_class.resource_kind if pawn.pawn_class != null else CG.ResourceKind.ENERGY
	u.move_speed = float(deps.move_speed.call(pawn))
	u.actions = _collect_player_actions(pawn)
	return u

static func _collect_player_actions(pawn: PawnData) -> Array[StringName]:
	var out: Array[StringName] = []
	if pawn.pawn_class != null:
		for a in pawn.pawn_class.starting_actions:
			if not out.has(a):
				out.append(a)
	for e in pawn.equipment():
		for a in e.granted_actions:
			if not out.has(a):
				out.append(a)
	return out

static func _build_enemy_unit(id: int, enemy_def: EnemyDef, enemy_id: StringName, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.ENEMY
	u.enemy_id = enemy_id
	u.position = pos
	if enemy_def == null:
		push_error("CombatSim.build: unknown enemy id '%s'" % enemy_id)
		u.display_name = String(enemy_id)
		u.hp_max = 1
		u.hp = 1
		return u
	u.display_name = enemy_def.display_name
	u.radius = enemy_def.radius
	u.hp_max = enemy_def.hp_max
	u.hp = u.hp_max
	u.resource_max = enemy_def.resource_max
	u.resource = u.resource_max
	u.resource_kind = enemy_def.resource_kind
	u.move_speed = enemy_def.move_speed
	u.actions = enemy_def.actions.duplicate()
	return u

# ---------------------------------------------------------------------------
# decide
# ---------------------------------------------------------------------------

static func _decide_phase(state: CombatState, deps: SimDeps) -> void:
	for unit in state.units:
		if not unit.alive or unit.intent != null or unit.is_busy():
			continue
		var intent: Intent = null
		if unit.pawn != null:
			intent = deps.plan_decide.call(state, unit)
		if intent == null:
			intent = deps.default_decide.call(state, unit)
		unit.intent = intent

# ---------------------------------------------------------------------------
# resolve
# ---------------------------------------------------------------------------

static func _resolve_phase(state: CombatState, deps: SimDeps) -> void:
	for unit in state.units:
		if not unit.alive:
			continue
		var intent := unit.intent
		if intent == null:
			continue
		unit.intent = null
		match intent.kind:
			CG.IntentKind.MOVE_TO:
				_resolve_move(unit, intent)
			CG.IntentKind.USE_ACTION:
				_resolve_use_action(state, unit, intent, deps)
			_:
				pass

static func _resolve_move(unit: CombatUnit, intent: Intent) -> void:
	var to_dest := intent.destination - unit.position
	var dist := to_dest.length()
	if dist <= unit.move_speed or dist <= 0.0001:
		unit.position = intent.destination
	else:
		unit.position += to_dest.normalized() * unit.move_speed

static func _resolve_use_action(state: CombatState, unit: CombatUnit, intent: Intent, deps: SimDeps) -> void:
	var action: ActionDef = deps.action_lookup.call(intent.action_id)
	if action == null:
		push_error("CombatSim: unit %d tried unknown action '%s'" % [unit.id, intent.action_id])
		return
	if unit.resource < action.resource_cost:
		return
	if unit.cooldowns.has(action.id) and state.tick < int(unit.cooldowns[action.id]):
		return

	## The seam's only reuse of an existing CombatUnit field: focus_id becomes
	## the in-flight action's target for the duration of the wind-up, which is
	## what lets range be measured again when the effect lands rather than at
	## commit. PlanInterpreter is free to set it ahead of an ACTION block; this
	## overwrites it with where the action actually aims, which is the same
	## value except when a targeting block aimed this one action elsewhere.
	unit.focus_id = intent.target_id
	unit.current_action = action.id
	unit.action_ticks_left = int(deps.wind_up_ticks.call(unit, action))

	if action.resource_cost > 0:
		unit.resource -= action.resource_cost
		var spent := _event(CG.EventKind.RESOURCE_SPENT, state.tick, unit.id, -1, action.id)
		spent.amount = action.resource_cost
		state.emit(spent)

	state.emit(_event(CG.EventKind.ACTION_START, state.tick, unit.id, intent.target_id, action.id))

	if unit.action_ticks_left <= 0:
		_fire_action(state, unit, action, deps)

# ---------------------------------------------------------------------------
# tick: wind-ups, recovery, statuses
# ---------------------------------------------------------------------------

static func _tick_phase(state: CombatState, deps: SimDeps) -> void:
	for unit in state.units:
		if not unit.alive:
			continue
		if unit.action_ticks_left > 0:
			unit.action_ticks_left -= 1
			if unit.action_ticks_left == 0 and unit.alive:
				var action: ActionDef = deps.action_lookup.call(unit.current_action)
				if action != null:
					_fire_action(state, unit, action, deps)
				else:
					unit.current_action = &""
		elif unit.recover_ticks_left > 0:
			unit.recover_ticks_left -= 1
			if unit.recover_ticks_left == 0:
				unit.current_action = &""
		_tick_statuses(state, unit)

static func _tick_statuses(state: CombatState, unit: CombatUnit) -> void:
	if unit.statuses.is_empty():
		return
	var expired: Array = unit.statuses.keys()
	expired.sort()
	for status in expired:
		if state.tick >= int(unit.statuses[status]):
			unit.statuses.erase(status)
			var e := _event(CG.EventKind.STATUS_EXPIRED, state.tick, -1, unit.id, &"")
			e.status = status
			state.emit(e)

# ---------------------------------------------------------------------------
# firing an action, applying its effect
# ---------------------------------------------------------------------------

static func _fire_action(state: CombatState, unit: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	state.emit(_event(CG.EventKind.ACTION_FIRE, state.tick, unit.id, unit.focus_id, action.id))

	for target in _resolve_targets(state, unit, action):
		_apply_action_effect(state, unit, target, action, deps)

	unit.current_action = action.id
	unit.action_ticks_left = 0
	unit.recover_ticks_left = int(deps.recover_ticks.call(unit, action))
	if action.cooldown_ticks > 0:
		unit.cooldowns[action.id] = state.tick + action.cooldown_ticks
	if unit.recover_ticks_left <= 0:
		unit.current_action = &""

## Range is measured here, at the moment the effect lands, against the target
## the action committed to. A target that walked out of range during the
## wind-up is a miss: ACTION_FIRE is still emitted (the log shows the attempt)
## but nothing else follows for it.
static func _resolve_targets(state: CombatState, unit: CombatUnit, action: ActionDef) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	var primary := state.unit(unit.focus_id)
	if primary == null or not primary.alive:
		return out
	if unit.position.distance_to(primary.position) > action.range_units:
		return out

	if action.splash_radius <= 0.0:
		out.append(primary)
		return out

	for other in state.living(primary.team):
		if other.position.distance_to(primary.position) <= action.splash_radius:
			out.append(other)
	return out

static func _apply_action_effect(state: CombatState, unit: CombatUnit, target: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	if not target.alive:
		return

	if action.heals:
		var amount := maxi(0, int(round(deps.attack_power.call(unit, action))))
		var before := target.hp
		target.hp = mini(target.hp_max, target.hp + amount)
		var applied := target.hp - before
		if applied > 0:
			var e := _event(CG.EventKind.HEAL, state.tick, unit.id, target.id, action.id)
			e.amount = applied
			e.damage_type = action.damage_type
			state.emit(e)
	else:
		var raw: float = deps.attack_power.call(unit, action)
		var reduction: float = clampf(deps.damage_reduction.call(target), 0.0, 1.0)
		var mitigated := maxi(0, int(round(raw * (1.0 - reduction))))
		var before := target.hp
		target.hp = maxi(0, target.hp - mitigated)
		var applied := before - target.hp
		var e := _event(CG.EventKind.DAMAGE, state.tick, unit.id, target.id, action.id)
		e.amount = applied
		e.amount_before_mitigation = int(round(raw))
		e.damage_type = action.damage_type
		state.emit(e)

	if action.applies_status_enabled:
		target.statuses[action.applies_status] = state.tick + action.status_duration_ticks
		var se := _event(CG.EventKind.STATUS_APPLIED, state.tick, unit.id, target.id, action.id)
		se.status = action.applies_status
		state.emit(se)

	if target.hp <= 0 and target.alive:
		target.alive = false
		state.emit(_event(CG.EventKind.DEATH, state.tick, unit.id, target.id, action.id))

# ---------------------------------------------------------------------------
# outcome
# ---------------------------------------------------------------------------

static func _check_outcome(state: CombatState) -> void:
	var player_alive := not state.living(CG.Team.PLAYER).is_empty()
	var enemy_alive := not state.living(CG.Team.ENEMY).is_empty()

	var outcome := CombatState.Outcome.UNRESOLVED
	if player_alive and not enemy_alive:
		outcome = CombatState.Outcome.PLAYER_WIN
	elif enemy_alive and not player_alive:
		outcome = CombatState.Outcome.ENEMY_WIN
	elif not player_alive and not enemy_alive:
		outcome = CombatState.Outcome.DRAW
	elif state.tick >= CG.MAX_TICKS:
		outcome = CombatState.Outcome.DRAW

	if outcome != CombatState.Outcome.UNRESOLVED:
		state.outcome = outcome
		state.emit(_event(CG.EventKind.FIGHT_END, state.tick, -1, -1, &""))

# ---------------------------------------------------------------------------

static func _event(kind: CG.EventKind, tick: int, source_id: int, target_id: int, action_id: StringName) -> CombatEvent:
	var e := CombatEvent.make(kind, tick)
	e.source_id = source_id
	e.target_id = target_id
	e.action_id = action_id
	return e
