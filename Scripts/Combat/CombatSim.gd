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
const Terrain := preload("res://Scripts/Core/Terrain.gd")
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
	state.terrain = encounter.terrain
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
		if unit.has_status(CG.Status.STUN):
			# No intent this tick -- a stunned unit neither decides nor acts.
			#
			# ISSUE 10'S INTERRUPT DECISION, FINAL: stun does NOT cancel an
			# action already committed before it landed. A unit mid-wind-up
			# when stunned still fires on schedule; is_busy() already keeps
			# it out of this loop regardless of the status, so this branch
			# only ever matters for a unit that was free to decide.
			#
			# Rejected: cancelling an in-flight wind-up on stun. That reading
			# is equally defensible (it rewards cheap actions under pressure
			# instead of rewarding a timed commitment) but costs more than it
			# buys here: it needs a resource-refund policy for anything spent
			# on commit, a decision about whether the target it was aimed at
			# still matters, and a new way for teal's content to reason about
			# "was this interrupted" -- none of which issue 10 asks for, and
			# all of which would land squarely in the middle of teal's
			# in-progress issue 7 tuning pass. A wind-up that is safe once
			# committed is also the simpler thing to teach a player: land the
			# stun before the swing starts, not during it.
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
				_resolve_move(state, unit, intent)
			CG.IntentKind.USE_ACTION:
				_resolve_use_action(state, unit, intent, deps)
			_:
				pass

## No pathfinding: a unit that cannot take its full step tries sliding along
## one axis at a time, and stays put only if neither axis is clear either.
## Enough for a room built from a few rectangles, per issue 13a's own scope;
## a unit that genuinely cannot route around an obstacle is a finding to
## report, not a pathfinder to build.
static func _resolve_move(state: CombatState, unit: CombatUnit, intent: Intent) -> void:
	var to_dest := intent.destination - unit.position
	var dist := to_dest.length()
	var step: Vector2
	if dist <= unit.move_speed or dist <= 0.0001:
		step = to_dest
	else:
		step = to_dest.normalized() * unit.move_speed

	var direct := _sweep(state, unit, step)
	if direct != unit.position:
		unit.position = direct
		return

	# The direct step made no progress at all (blocked immediately, not just
	# short of the full distance). Try sliding along one axis instead of
	# freezing.
	#
	# Issue 30: this used to slide with Vector2(step.x, 0.0) / Vector2(0.0,
	# step.y) -- the x/y *component* of the diagonal step, not a full step on
	# that axis. Near a corner where one axis is fully blocked, the unit's
	# remaining distance is dominated by the blocked axis, so the angle to
	# the target keeps flattening as the open axis closes in -- and the open
	# axis's component of a fixed-length diagonal shrinks with that angle.
	# The result was a real, measured, unit ever more slowly and never
	# hitting zero within any fixed number of ticks: an asymptote a 3600-tick
	# fight cap can't tell from frozen. Each axis now gets its own full
	# move_speed (capped at how far it actually has left to go on that axis
	# alone), so slide progress no longer depends on the angle of a step it
	# isn't taking.
	var slide_x := _sweep(state, unit, Vector2(_axis_step(to_dest.x, unit.move_speed), 0.0))
	var slide_y := _sweep(state, unit, Vector2(0.0, _axis_step(to_dest.y, unit.move_speed)))
	var moved_x := slide_x != unit.position
	var moved_y := slide_y != unit.position

	if moved_x and moved_y:
		unit.position = slide_x if absf(step.x) >= absf(step.y) else slide_y
	elif moved_x:
		unit.position = slide_x
	elif moved_y:
		unit.position = slide_y
	# else: fully blocked in every direction this tick. Stay put.

## A single axis's full step: move_speed toward `remaining`, capped so it
## does not overshoot the destination on that axis alone. Zero if there is
## nothing left to close on this axis.
static func _axis_step(remaining: float, move_speed: float) -> float:
	return clampf(remaining, -move_speed, move_speed)

## Walks `step` in small increments and returns the furthest point actually
## reached before hitting something solid -- `unit.position` unchanged if
## even the first increment is blocked. This is what stops a unit faster
## than a wall is thick from tunneling straight through it:
## `Terrain.point_is_blocked` alone only checks the landing point, and a
## single large jump can clear a thin wall without either endpoint ever
## registering as inside it. Doubles as "stop at the wall" for a head-on
## approach with no clear slide axis, which is the "stop" half of "slide
## along it or stop" -- no pathfinding, just don't pass through.
const _MOVE_SWEEP_STEP := 4.0

static func _sweep(state: CombatState, unit: CombatUnit, step: Vector2) -> Vector2:
	var length := step.length()
	if length <= 0.0001:
		return unit.position
	var direction := step / length
	var travelled := 0.0
	var last_good := unit.position
	while travelled < length:
		travelled = minf(travelled + _MOVE_SWEEP_STEP, length)
		var candidate := _clamp_to_arena(unit.position + direction * travelled)
		if Terrain.point_is_blocked(state.terrain, candidate, unit.radius):
			break
		last_good = candidate
	return last_good

## Nothing previously compared a unit's position to the arena bounds, so a
## unit told to walk past the edge just kept going -- issue 16 measured
## survivors twenty arena widths off the map after a full fight. Clamped
## here, in the simulation, not in the view: the view drawing a unit at the
## edge while the simulation thinks it is elsewhere would be worse than the
## bug it replaces. A destination outside the arena still moves the unit
## partway (whatever move_speed allows) and lands it on the boundary rather
## than refusing to move at all.
static func _clamp_to_arena(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, -CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_WIDTH),
		clampf(p.y, -CG.ARENA_HALF_HEIGHT, CG.ARENA_HALF_HEIGHT)
	)

## HASTE scales wind-up and recovery ticks by deps.haste_tick_scale, floored
## at 1 tick so a hasted unit can never act instantaneously. Read at the
## moment ticks are computed (commit for wind-up, landing for recovery), not
## cached, so HASTE applied or removed mid-action changes the *next*
## computation rather than reaching back into one already in flight.
static func _apply_haste(unit: CombatUnit, deps: SimDeps, ticks: int) -> int:
	if ticks <= 0 or not unit.has_status(CG.Status.HASTE):
		return ticks
	var scale: float = deps.haste_tick_scale.call(unit)
	return maxi(1, int(round(float(ticks) * scale)))

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
	unit.action_ticks_left = _apply_haste(unit, deps, int(deps.wind_up_ticks.call(unit, action)))

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
		_tick_regen(state, unit, deps)
		_tick_dot_statuses(state, unit, deps)
		_tick_statuses(state, unit)
		_tick_hazards(state, unit)

## Mana and Energy refill over time; Rage does not — CombatSim enforces that
## itself rather than trusting the rate function, so a rate that forgets to
## special-case Rage still cannot make it climb. Fractional rates are rounded
## stochastically against state.rng rather than dropped, so "0.3 per tick"
## still averages out over a fight instead of always rounding to 0 (and stays
## reproducible for the same seed).
static func _tick_regen(state: CombatState, unit: CombatUnit, deps: SimDeps) -> void:
	if unit.resource_kind == CG.ResourceKind.RAGE:
		return
	var gained := _stochastic_round(state, deps.resource_regen_per_tick.call(unit))
	if gained > 0:
		unit.resource = clampi(unit.resource + gained, 0, unit.resource_max)

static func _stochastic_round(state: CombatState, value: float) -> int:
	if value <= 0.0:
		return 0
	var whole := int(floor(value))
	var frac := value - float(whole)
	if frac > 0.0 and state.rng.randf() < frac:
		whole += 1
	return whole

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

## BURN and POISON deal their damage every tick they are active, with a
## DAMAGE event per hit so the log and floaters see it -- the same
## membership-driven shape as hazard damage, and for the same reason: no
## event, no visible cause, and CombatEvent exists specifically to prevent
## that. Fires before _tick_statuses checks expiry, so the tick a status
## expires on still deals its damage; the tick after, it does not, matching
## the hazard "stops the tick after it leaves" behaviour.
const _DOT_STATUSES := {
	CG.Status.BURN: CG.DamageType.FIRE,
	CG.Status.POISON: CG.DamageType.PROFANE,
}

static func _tick_dot_statuses(state: CombatState, unit: CombatUnit, deps: SimDeps) -> void:
	for status in _DOT_STATUSES:
		if not unit.has_status(status):
			continue
		var amount := _stochastic_round(state, deps.status_damage_per_tick.call(unit, status))
		if amount <= 0:
			continue
		var before := unit.hp
		unit.hp = maxi(0, unit.hp - amount)
		var applied := before - unit.hp
		var e := _event(CG.EventKind.DAMAGE, state.tick, -1, unit.id, &"")
		e.amount = applied
		e.damage_type = _DOT_STATUSES[status]
		e.status = status
		state.emit(e)
		if unit.hp <= 0 and unit.alive:
			unit.alive = false
			state.emit(_event(CG.EventKind.DEATH, state.tick, -1, unit.id, &""))
			return

## A unit standing in a HAZARD takes its damage every tick it is inside, with
## an event per hit so the log and floaters see it, and stops the tick after
## it leaves -- membership is just re-checked each tick, no decay to track.
static func _tick_hazards(state: CombatState, unit: CombatUnit) -> void:
	if state.terrain.is_empty():
		return
	for hazard in Terrain.hazards_at(state.terrain, unit.position):
		if hazard.damage_per_tick <= 0:
			continue
		var before := unit.hp
		unit.hp = maxi(0, unit.hp - hazard.damage_per_tick)
		var applied := before - unit.hp
		var e := _event(CG.EventKind.DAMAGE, state.tick, -1, unit.id, &"")
		e.amount = applied
		e.damage_type = hazard.damage_type
		state.emit(e)
		if unit.hp <= 0 and unit.alive:
			unit.alive = false
			state.emit(_event(CG.EventKind.DEATH, state.tick, -1, unit.id, &""))
			return

# ---------------------------------------------------------------------------
# firing an action, applying its effect
# ---------------------------------------------------------------------------

static func _fire_action(state: CombatState, unit: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	state.emit(_event(CG.EventKind.ACTION_FIRE, state.tick, unit.id, unit.focus_id, action.id))

	var targets := _resolve_targets(state, unit, action)
	if targets.is_empty():
		state.emit(_event(CG.EventKind.MISS, state.tick, unit.id, unit.focus_id, action.id))
	for target in targets:
		_apply_action_effect(state, unit, target, action, deps)

	## Rage gains only from a landed hit, not from committing or from a miss:
	## a Rage pawn swinging at nothing (out of range at landing) must not
	## fill, per issue 4's own acceptance criterion for it.
	if not targets.is_empty() and unit.resource_kind == CG.ResourceKind.RAGE:
		var gained := _stochastic_round(state, deps.rage_gain_on_attack.call(unit))
		if gained > 0:
			unit.resource = clampi(unit.resource + gained, 0, unit.resource_max)

	unit.current_action = action.id
	unit.action_ticks_left = 0
	unit.recover_ticks_left = _apply_haste(unit, deps, int(deps.recover_ticks.call(unit, action)))
	if action.cooldown_ticks > 0:
		unit.cooldowns[action.id] = state.tick + action.cooldown_ticks
	if unit.recover_ticks_left <= 0:
		unit.current_action = &""

## Range and line of sight are both measured here, at the moment the effect
## lands, against the target the action committed to -- same reasoning for
## both: a target that walked out of range, or behind a wall, during the
## wind-up is a miss (issue 28), and one that steps back into range or out
## from behind cover is a hit. ACTION_FIRE is still emitted either way (the
## log shows the attempt) but nothing else follows for a miss.
static func _resolve_targets(state: CombatState, unit: CombatUnit, action: ActionDef) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	var primary := state.unit(unit.focus_id)
	if primary == null or not primary.alive:
		return out
	if unit.position.distance_to(primary.position) > action.range_units:
		return out
	if action.requires_line_of_sight and Terrain.line_is_blocked(state.terrain, unit.position, primary.position):
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
		var amount := maxi(0, int(round(deps.attack_power.call(unit, action, state.rng))))
		var before := target.hp
		target.hp = mini(target.hp_max, target.hp + amount)
		var applied := target.hp - before
		if applied > 0:
			var e := _event(CG.EventKind.HEAL, state.tick, unit.id, target.id, action.id)
			e.amount = applied
			e.damage_type = action.damage_type
			state.emit(e)
	else:
		var raw: float = deps.attack_power.call(unit, action, state.rng)
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
