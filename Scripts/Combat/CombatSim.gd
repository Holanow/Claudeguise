extends RefCounted
class_name CombatSim


## The simulation. Owns every mutation of a CombatUnit and every event emitted.

## Layout-only fallback spacing for party members past the encounter's spawn
## list. Not a combat number: nothing here affects hp, damage or speed.
const _FALLBACK_SPAWN_SPACING := 32.0

## How many ticks a pull takes to drag its target, and how long that target is
## stunned for: one number, because the stun IS the pull.
const PULL_TICKS := 7

## Builds the starting state: places both sides, derives hp and resources
## through `deps`, and emits FIGHT_START.
static func build(party: Array[PawnData], encounter: Encounter, fight_seed: int, deps: SimDeps = null) -> CombatState:
	if deps == null:
		deps = SimDeps.new()
	var state := CombatState.new(fight_seed)
	## Issue 492: the state owns its terrain, because terrain is mutable now.
	## Sharing the encounter's array was harmless while nothing ever wrote to it
	## and is not any more: pools were being written back into the room, so the
	## next fight in the same process started in the last one's puddles.
	state.terrain = encounter.terrain.duplicate()
	var next_id := 0

	for i in party.size():
		var unit := _build_player_unit(next_id, party[i], party_spawn_position(encounter, i), deps)
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
	_tick_projectiles(state, deps)
	_check_outcome(state, deps)

## Runs to completion. Used by tests and by the headless balance checks; the
## battle view calls step() itself so it can draw between ticks.
static func run(state: CombatState, deps: SimDeps = null) -> CombatState.Outcome:
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		step(state, deps)
	return state.outcome

# ---------------------------------------------------------------------------
# build() helpers
# ---------------------------------------------------------------------------

## Public since issue 145, on finch's `default_attack_action` precedent: the
## deploy screen has to open showing where each pawn *would* have started, and a
## screen that reimplemented the overflow rule would drift from the fight it is
## meant to be previewing. One rule, asked rather than copied.
static func party_spawn_position(encounter: Encounter, index: int) -> Vector2:
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
	u.resource_kind = pawn.pawn_class.resource_kind if pawn.pawn_class != null else CG.ResourceKind.ENERGY
	u.resource = int(deps.starting_resource.call(u.resource_kind, u.resource_max))
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

static func _build_enemy_unit(id: int, enemy_def: EnemyDef, enemy_id: StringName, pos: Vector2, team: CG.Team = CG.Team.ENEMY) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
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
		if not unit.alive:
			continue
		## Checked BEFORE the busy guard, which is the whole of the #121 change.
		if unit.has_status(CG.Status.STUN):
			_interrupt_on_stun(state, unit)
			continue
		if unit.intent != null or unit.is_busy():
			continue
		## THE COMPULSION, and it sits here rather than in the decision layer
		## for one reason: it has to beat a stated plan. See `_compelling_taunter`.
		var taunter := _compelling_taunter(state, unit)
		if taunter != null:
			unit.intent = _compelled_intent(unit, taunter, deps)
			_reaffirm_sustain(state, unit, unit.intent)
			continue
		var intent: Intent = null
		if unit.pawn != null:
			intent = deps.plan_decide.call(state, unit)
		if intent == null:
			intent = deps.default_decide.call(state, unit)
		unit.intent = intent
		_reaffirm_sustain(state, unit, intent)

## A stunned unit neither decides nor acts, and does not finish what it had
## started: the wind-up is thrown away, not resumed.
static func _interrupt_on_stun(state: CombatState, unit: CombatUnit) -> void:
	unit.intent = null
	if unit.action_ticks_left > 0:
		var e := _event(CG.EventKind.INTERRUPTED, state.tick, unit.id, -1, unit.current_action)
		e.amount = maxi(0, unit.action_ticks_total - unit.action_ticks_left)
		state.emit(e)
		unit.current_action = &""
		unit.action_ticks_left = 0
		unit.action_ticks_total = 0
	_end_sustain(state, unit)

# ---------------------------------------------------------------------------
# taunt as a compulsion (issues 58, 121, 132)
# ---------------------------------------------------------------------------
#
# The player: *"Taunted pawns should be forced to move into range and use their
# default attack on the enemy that taunted them."*
#
# As built it also beats a stated plan: while TAUNTED, `_decide_phase` never
# reaches the plan layer at all. Issue 379.

## Who this unit is compelled by, or null.
static func _compelling_taunter(state: CombatState, unit: CombatUnit) -> CombatUnit:
	if not unit.has_status(CG.Status.TAUNTED):
		return null
	var taunter := state.unit(int(unit.status_magnitude.get(CG.Status.TAUNTED, -1.0)))
	if taunter != null and taunter.alive:
		return taunter
	_remove_status(unit, CG.Status.TAUNTED)
	var e := _event(CG.EventKind.STATUS_EXPIRED, state.tick, -1, unit.id, &"")
	e.status = CG.Status.TAUNTED
	state.emit(e)
	return null

## Move into range, then use the default attack on the taunter, and nothing
## else: a compelled pawn IS made to stop healing itself, because the branch
## that calls this never reaches the plan layer. Issue 379.
static func _compelled_intent(unit: CombatUnit, taunter: CombatUnit, deps: SimDeps) -> Intent:
	var defs: Array[ActionDef] = []
	for id in unit.actions:
		var a: ActionDef = deps.action_lookup.call(id)
		if a != null:
			defs.append(a)
	var dist := unit.position.distance_to(taunter.position)
	var melee: ActionDef = deps.default_attack_action.call(defs, false)
	var ranged: ActionDef = deps.default_attack_action.call(defs, true)
	var chosen: ActionDef = melee
	if melee == null or dist > melee.range_units:
		chosen = ranged if ranged != null else melee
	## Issue 155: both carry `Intent.COMPELLED` so the log can say the pawn was
	## dragged rather than letting a compulsion look like the fallback deciding.
	if chosen == null or dist > chosen.range_units:
		return Intent.move_to(taunter.position, Intent.COMPELLED)
	return Intent.use_action(chosen.id, taunter.id, Intent.COMPELLED)

## Puts TAUNTED on everyone the taunt reaches, at the moment it is applied.
static func _broadcast_taunt(state: CombatState, taunter: CombatUnit, ticks: int) -> void:
	if taunter.taunt_radius <= 0.0 or ticks <= 0:
		return
	for victim in state.living(_enemy_team(taunter.team)):
		if taunter.position.distance_to(victim.position) > taunter.taunt_radius:
			continue
		## Two taunters split a party instead of both piling onto one pawn.
		## Issue 309: dormant in today's content, which spawns one Brute per
		## room and allows one Warrior per party, so no side ever fields two.
		if _compelling_taunter(state, victim) != null:
			continue
		victim.statuses[CG.Status.TAUNTED] = state.tick + ticks
		victim.status_magnitude[CG.Status.TAUNTED] = float(taunter.id)
		## The one status applied outside `_apply_status`, so it stamps its own
		## source rather than leaving the field lying about who taunted.
		victim.status_source[CG.Status.TAUNTED] = taunter.id
		var e := _event(CG.EventKind.STATUS_APPLIED, state.tick, taunter.id, victim.id, &"")
		e.status = CG.Status.TAUNTED
		state.emit(e)

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
				_resolve_move(state, unit, intent, deps)
			CG.IntentKind.USE_ACTION:
				_resolve_use_action(state, unit, intent, deps)
			_:
				_resolve_idle(state, unit, deps)

## A unit that spends its tick doing nothing recovers resource faster than one
## that spends it moving or fighting, so "wait for mana" is a thing a plan can
## express.
static func _resolve_idle(state: CombatState, unit: CombatUnit, deps: SimDeps) -> void:
	if unit.resource_kind == CG.ResourceKind.RAGE:
		return
	if unit.resource >= unit.resource_max:
		return
	var scale: float = deps.idle_resource_regen_scale.call(unit)
	if scale <= 1.0:
		return
	var base: float = deps.resource_regen_per_tick.call(unit)
	var gained := _stochastic_round(state, base * (scale - 1.0))
	if gained > 0:
		unit.resource = clampi(unit.resource + gained, 0, unit.resource_max)

## No pathfinding: a unit that cannot take its full step tries sliding along
## one axis at a time, and stays put only if neither axis is clear either.
static func _resolve_move(state: CombatState, unit: CombatUnit, intent: Intent, deps: SimDeps) -> void:
	var before := unit.position
	var to_dest := intent.destination - unit.position
	var dist := to_dest.length()
	var speed := _effective_move_speed(unit, deps)
	var step: Vector2
	if dist <= speed or dist <= 0.0001:
		step = to_dest
	else:
		step = to_dest.normalized() * speed

	var direct := _sweep(state, unit, step)
	if direct != unit.position:
		unit.position = _avoid_hazard(state, unit, to_dest, speed, direct)
		_update_facing_from_movement(unit, before)
		return

	var slide_x := _sweep(state, unit, Vector2(_axis_step(to_dest.x, speed), 0.0))
	var slide_y := _sweep(state, unit, Vector2(0.0, _axis_step(to_dest.y, speed)))
	var moved_x := slide_x != unit.position
	var moved_y := slide_y != unit.position

	if moved_x and moved_y:
		unit.position = slide_x if absf(step.x) >= absf(step.y) else slide_y
	elif moved_x:
		unit.position = slide_x
	elif moved_y:
		unit.position = slide_y
	# else: fully blocked in every direction this tick. Stay put.
	_update_facing_from_movement(unit, before)

## Issue 163: a step that would end in fire gives way to a clear one, when a
## clear one exists that still makes progress.
static func _avoid_hazard(state: CombatState, unit: CombatUnit, to_dest: Vector2, speed: float, direct: Vector2) -> Vector2:
	if state.terrain.is_empty() or not _hazard_harms(state, direct):
		return direct
	var goal := unit.position + to_dest
	if to_dest.length() <= 0.0001:
		return direct
	var step_direction := to_dest.normalized()
	var best := direct
	var best_gap := goal.distance_to(unit.position)
	var turn := step_direction.rotated(PI / 4.0) * speed
	var turn_back := step_direction.rotated(-PI / 4.0) * speed
	for candidate in [
		_sweep(state, unit, turn),
		_sweep(state, unit, turn_back),
		_sweep(state, unit, Vector2(_axis_step(to_dest.x, speed), 0.0)),
		_sweep(state, unit, Vector2(0.0, _axis_step(to_dest.y, speed))),
	]:
		if candidate == unit.position or _hazard_harms(state, candidate):
			continue
		var gap := goal.distance_to(candidate)
		if gap < best_gap:
			best_gap = gap
			best = candidate
	return best

## Whether standing at `p` would cost a unit anything, for callers outside this
## file.
static func standing_harms(state: CombatState, p: Vector2) -> bool:
	return _hazard_harms(state, p)

## Whether standing at `p` costs a unit anything. Damage or a status -- a tar pit
## deals no damage at all and is still somewhere a unit should rather not stand,
## so both count, and a decorative hazard authored with neither is correctly
## ignored.
static func _hazard_harms(state: CombatState, p: Vector2) -> bool:
	for hazard in Terrain.hazards_at(state.terrain, p):
		if hazard.damage_per_tick > 0:
			return true
		if hazard.applies_status_enabled and hazard.status_duration_ticks > 0:
			return true
	return false

## `CombatUnit.facing` only changes when a unit actually displaces this tick --
## a blocked or idle unit keeps whatever it last faced rather than snapping to
## zero, so SHIELDING's front-arc check still has something meaningful to read
## while a unit is stalled at a wall or fully boxed in.
static func _update_facing_from_movement(unit: CombatUnit, before: Vector2) -> void:
	if unit.position != before:
		unit.facing = (unit.position - before).normalized()

## Set at the moment a unit commits to USE_ACTION, alongside focus_id, so it
## persists through the wind-up the same way focus_id already does -- a unit
## keeps facing what it is fighting for the whole time it is committed to
## hitting it, not just the instant it decided to. Left unchanged if the
## target id does not resolve to a living unit (nothing to face) or the unit
## is already standing exactly on top of it (no direction to derive).
static func _update_facing_toward(state: CombatState, unit: CombatUnit, target_id: int) -> void:
	var target := state.unit(target_id)
	if target == null:
		return
	var dir := target.position - unit.position
	if dir.length() > 0.0001:
		unit.facing = dir.normalized()

## A single axis's full step: move_speed toward `remaining`, capped so it
## does not overshoot the destination on that axis alone. Zero if there is
## nothing left to close on this axis.
static func _axis_step(remaining: float, move_speed: float) -> float:
	return clampf(remaining, -move_speed, move_speed)

## Issue 14: SLOWED scales movement the same way HASTE already scales action
## ticks -- deps.slowed_speed_scale is a SimDeps seam, not a hardcoded
## multiplier, so content owns the number. Read fresh every time a move
## resolves rather than cached on the unit, so applying or removing SLOWED
## mid-fight changes the very next step rather than reaching back into one
## already computed.
static func _effective_move_speed(unit: CombatUnit, deps: SimDeps) -> float:
	if not unit.has_status(CG.Status.SLOWED):
		return unit.move_speed
	var scale: float = deps.slowed_speed_scale.call(unit)
	return maxf(0.0, unit.move_speed * scale)

## Walks `step` in small increments and returns the furthest point actually
## reached before hitting something solid -- `unit.position` unchanged if
## even the first increment is blocked. This is what stops a unit faster
## than a wall is thick from tunneling straight through it:
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

	if action.sustain_cost_per_tick > 0 and unit.sustaining == action.id:
		return

	if unit.resource < action.resource_cost:
		return
	if unit.cooldowns.has(action.id) and state.tick < int(unit.cooldowns[action.id]):
		return

	unit.focus_id = intent.target_id
	_update_facing_toward(state, unit, intent.target_id)
	unit.current_action = action.id
	unit.action_ticks_left = _apply_haste(unit, deps, int(deps.wind_up_ticks.call(unit, action)))
	unit.action_ticks_total = unit.action_ticks_left

	if action.resource_cost > 0:
		unit.resource -= action.resource_cost
		var spent := _event(CG.EventKind.RESOURCE_SPENT, state.tick, unit.id, -1, action.id)
		spent.amount = action.resource_cost
		state.emit(spent)

	## Issue 155: the one place the decision layer's answer survives its own tick.
	var started := _event(CG.EventKind.ACTION_START, state.tick, unit.id, intent.target_id, action.id)
	started.source_plan = intent.source_plan
	state.emit(started)

	if unit.action_ticks_left <= 0:
		_fire_action(state, unit, action, deps)

# ---------------------------------------------------------------------------
# tick: wind-ups, recovery, statuses
# ---------------------------------------------------------------------------

static func _tick_phase(state: CombatState, deps: SimDeps) -> void:
	for unit in state.units:
		if not unit.alive:
			if unit.sustaining != &"":
				_end_sustain(state, unit)
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
		_tick_pull(state, unit)
		_tick_regen(state, unit, deps)
		_tick_sustain(state, unit, deps)
		_tick_dot_statuses(state, unit, deps)
		_tick_statuses(state, unit, deps)
		_tick_hazards(state, unit)
		if not unit.alive and unit.sustaining != &"":
			_end_sustain(state, unit)

## Mana and Energy refill over time; Rage does not -- CombatSim enforces that
## itself rather than trusting the rate function, so a rate that forgets to
## special-case Rage still cannot make it climb. Fractional rates are rounded
## stochastically against state.rng rather than dropped, so "0.3 per tick"
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

## Keys are sorted before iterating because a Dictionary's key order is insertion
## order -- the order the statuses happened to land in during a fight.
static func _tick_statuses(state: CombatState, unit: CombatUnit, deps: SimDeps) -> void:
	if unit.statuses.is_empty():
		return
	var expired: Array = unit.statuses.keys()
	expired.sort()
	for status in expired:
		if state.tick >= int(unit.statuses[status]):
			if _decay_one_stack(state, unit, status, deps):
				continue
			## `_remove_status` also resets the two fields that shadow a status:
			_remove_status(unit, status)
			var e := _event(CG.EventKind.STATUS_EXPIRED, state.tick, -1, unit.id, &"")
			e.status = status
			state.emit(e)

## True when one stack came off and the status survives, so the caller leaves it
## alone. False for everything else, which is every status that does not stack
## and the last stack of one that does.
static func _decay_one_stack(state: CombatState, unit: CombatUnit, status: CG.Status, deps: SimDeps) -> bool:
	if not _STACKING_STATUSES.has(status):
		return false
	var remaining := float(unit.status_magnitude.get(status, 0.0)) - 1.0
	if remaining < 1.0:
		return false
	var window: int = int(deps.status_stack_decay_ticks.call(status))
	if window <= 0:
		return false
	unit.status_magnitude[status] = remaining
	unit.statuses[status] = state.tick + window
	return true

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
	CG.Status.BLEED: CG.DamageType.PHYSICAL,
}

## THREE STATUSES, THREE SCALING RULES, one expression:
static func _tick_dot_statuses(state: CombatState, unit: CombatUnit, deps: SimDeps) -> void:
	for status in _DOT_STATUSES:
		if not unit.has_status(status):
			continue
		var interval: int = maxi(1, int(deps.status_tick_interval.call(status)))
		if state.tick % interval != 0:
			continue
		var rate: float = deps.status_damage_per_tick.call(unit, status)
		var magnitude := float(unit.status_magnitude.get(status, 0.0))
		if magnitude > 0.0:
			rate += float(deps.status_damage_per_magnitude.call(unit, status)) * magnitude
		var amount := _stochastic_round(state, rate)
		if amount <= 0:
			continue
		## Whoever applied the status, or -1 when terrain did. Read by key, never
		## iterated, so it adds no order for a seed to diverge on.
		var source := int(unit.status_source.get(status, -1))
		var before := unit.hp
		unit.hp = maxi(0, unit.hp - amount)
		var applied := before - unit.hp
		var e := _event(CG.EventKind.DAMAGE, state.tick, source, unit.id, &"")
		e.amount = applied
		e.damage_type = _DOT_STATUSES[status]
		e.status = status
		state.emit(e)
		if _kill_if_dead(state, unit, source, &""):
			return

## A tar pit: terrain that applies a status rather than dealing damage.
static func _apply_hazard_status(state: CombatState, unit: CombatUnit, hazard) -> void:
	if not hazard.applies_status_enabled or hazard.status_duration_ticks <= 0:
		return
	var status: CG.Status = hazard.applies_status
	## No `status_source` write: terrain has no unit id, and a hazard refreshing
	## a burn somebody else lit leaves that burn theirs, as `maxf` does below.
	var entering := not unit.has_status(status)
	unit.statuses[status] = state.tick + hazard.status_duration_ticks
	## `maxf`, so standing in a weak fire never waters down a fiercer burn a hit
	## already applied -- the same rule `_apply_status` uses for a hit-scaled status.
	if hazard.status_magnitude > 0.0:
		var carried := float(unit.status_magnitude.get(status, 0.0))
		unit.status_magnitude[status] = maxf(carried, hazard.status_magnitude)
	if entering:
		var e := _event(CG.EventKind.STATUS_APPLIED, state.tick, -1, unit.id, &"")
		e.status = status
		e.amount = int(unit.status_magnitude.get(status, 0.0))
		state.emit(e)

## A unit standing in a HAZARD takes its damage every tick it is inside, with
## an event per hit so the log and floaters see it, and stops the tick after
## it leaves -- membership is just re-checked each tick, no decay to track.
static func _tick_hazards(state: CombatState, unit: CombatUnit) -> void:
	if state.terrain.is_empty():
		return
	for hazard in Terrain.hazards_at(state.terrain, unit.position):
		_apply_hazard_status(state, unit, hazard)
		if hazard.damage_per_tick <= 0:
			continue
		var before := unit.hp
		unit.hp = maxi(0, unit.hp - hazard.damage_per_tick)
		var applied := before - unit.hp
		var e := _event(CG.EventKind.DAMAGE, state.tick, -1, unit.id, &"")
		e.amount = applied
		e.damage_type = hazard.damage_type
		state.emit(e)
		if _kill_if_dead(state, unit, -1, &""):
			return

# ---------------------------------------------------------------------------
# firing an action, applying its effect
# ---------------------------------------------------------------------------

static func _fire_action(state: CombatState, unit: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	state.emit(_event(CG.EventKind.ACTION_FIRE, state.tick, unit.id, unit.focus_id, action.id))

	if action.summons_unit_id != &"":
		_spawn_summon(state, unit, action, deps)

	if action.sustain_cost_per_tick > 0:
		_begin_sustain(state, unit, action)
	else:
		var targets := _resolve_targets(state, unit, action)
		if targets.is_empty():
			state.emit(_event(CG.EventKind.MISS, state.tick, unit.id, unit.focus_id, action.id))
		elif action.projectile_speed > 0.0:
			_spawn_projectile(state, unit, targets[0], action, deps)
		else:
			for target in targets:
				_apply_action_effect(state, unit, target, action, deps)
			_on_hit_landed(state, unit, action, deps, targets[0].position)

	unit.current_action = action.id
	unit.action_ticks_left = 0
	unit.action_ticks_total = 0
	unit.recover_ticks_left = _apply_haste(unit, deps, int(deps.recover_ticks.call(unit, action)))
	if action.cooldown_ticks > 0:
		unit.cooldowns[action.id] = state.tick + action.cooldown_ticks
	if unit.recover_ticks_left <= 0:
		unit.current_action = &""

## Everything a source gains from a hit that actually connected: Rage, and issue
## 165's `ActionDef.restores_resource`.
static func _on_hit_landed(state: CombatState, source: CombatUnit, action: ActionDef, deps: SimDeps, at: Vector2 = Vector2.ZERO) -> void:
	if action != null and action.leaves_pool_radius > 0.0:
		_leave_pool(state, source, action, at)
	if action != null and action.restores_resource > 0:
		source.resource = clampi(source.resource + action.restores_resource, 0, source.resource_max)
	if source.resource_kind != CG.ResourceKind.RAGE:
		return
	var gained := _stochastic_round(state, deps.rage_gain_on_attack.call(source))
	if gained > 0:
		source.resource = clampi(source.resource + gained, 0, source.resource_max)

## Issue 174: Rage also fills from being HIT, not only from hitting.
static func _on_damage_taken(state: CombatState, target: CombatUnit, applied: int, deps: SimDeps) -> void:
	if applied <= 0 or not target.alive:
		return
	if target.resource_kind != CG.ResourceKind.RAGE:
		return
	var gained := _stochastic_round(state, deps.rage_gain_on_damage_taken.call(target, applied))
	if gained > 0:
		target.resource = clampi(target.resource + gained, 0, target.resource_max)

# ---------------------------------------------------------------------------
# terrain that appears mid-fight (issue 492)
# ---------------------------------------------------------------------------

## The one place `state.terrain` changes after `build()`. Water and fire
## annihilate the ground they share: the fire keeps what the pool did not cover
## and the pool keeps what the fire did not, each as up to four parts.
static func _leave_pool(state: CombatState, caster: CombatUnit, action: ActionDef, at: Vector2) -> void:
	var half := action.leaves_pool_radius
	var pool_parts: Array[Rect2] = [Rect2(at.x - half, at.y - half, half * 2.0, half * 2.0)]
	var kept: Array = []
	for feature in state.terrain:
		if not Terrain.is_burning(feature) or pool_parts.is_empty():
			kept.append(feature)
			continue
		var fire_parts: Array[Rect2] = [feature.rect]
		var surviving_pool: Array[Rect2] = []
		var touched := false
		for p in pool_parts:
			var cut: Array[Rect2] = []
			for fr in fire_parts:
				if fr.intersects(p):
					touched = true
					cut.append_array(Terrain.subtract(fr, p))
				else:
					cut.append(fr)
			fire_parts = cut
			surviving_pool.append_array(Terrain.subtract(p, feature.rect))
		pool_parts = surviving_pool
		if not touched:
			kept.append(feature)
			continue
		_emit_terrain(state, CG.EventKind.TERRAIN_REMOVED, caster, action,
			feature.kind, feature.rect, CG.TerrainChange.DOUSED)
		for fr in fire_parts:
			var part = _copy_feature(feature, fr)
			kept.append(part)
			_emit_terrain(state, CG.EventKind.TERRAIN_ADDED, caster, action,
				part.kind, fr, CG.TerrainChange.DOUSED)
	## Issue 554: one pool, painted. Every cast stamps the same water feature
	## rather than appending its own, so overlapping casts fuse instead of
	## stacking; a stamp landing on ground that is already wet stores nothing.
	var pool_feature = _water_feature(kept)
	for pr in pool_parts:
		if pool_feature == null:
			pool_feature = Terrain.pool(pr)
			kept.append(pool_feature)
		elif not Terrain.paint(pool_feature, pr):
			continue
		_emit_terrain(state, CG.EventKind.TERRAIN_ADDED, caster, action,
			Terrain.Kind.WATER, pr, CG.TerrainChange.CAST)
	## Replaced in place, never reassigned: `BattleView` hands `state.terrain` to
	## `ArenaFloor` once at fight start, so a new array leaves the view drawing
	## the room as authored forever. Same contract `state.units` already has.
	state.terrain.assign(kept)

## The fight's one pool, or null before anything has been cast. There is at most
## one: nothing ever splits a water feature, and every cast paints into this one.
static func _water_feature(features: Array):
	for f in features:
		if f.kind == Terrain.Kind.WATER:
			return f
	return null

## The same feature over a different rect. Every field is copied rather than the
## damaging ones only, so a split tar pit stays a tar pit.
static func _copy_feature(f, rect: Rect2):
	var out := Terrain.make(f.kind, rect)
	out.damage_per_tick = f.damage_per_tick
	out.damage_type = f.damage_type
	out.applies_status = f.applies_status
	out.applies_status_enabled = f.applies_status_enabled
	out.status_duration_ticks = f.status_duration_ticks
	out.status_magnitude = f.status_magnitude
	out.parts = f.parts.duplicate()
	return out

static func _emit_terrain(state: CombatState, kind: CG.EventKind, caster: CombatUnit, action: ActionDef, terrain_kind, rect: Rect2, change: CG.TerrainChange) -> void:
	var e := _event(kind, state.tick, caster.id, -1, action.id)
	e.terrain_kind = terrain_kind
	e.terrain_rect = rect
	e.terrain_change = change
	state.emit(e)

## Issue 12: the one place `state.units` grows after `build()`. Appends only --
## never inserts, never reorders -- so a new unit's id is `state.units.size()`
static func _spawn_summon(state: CombatState, caster: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	var enemy_def: EnemyDef = deps.enemy_lookup.call(action.summons_unit_id)
	var new_id := state.units.size()
	var summon := _build_enemy_unit(new_id, enemy_def, action.summons_unit_id, caster.position, caster.team)
	state.units.append(summon)
	## Issue 193. Emitted after the append, so `state.unit(target_id)` already
	## resolves for anything reading the event on this tick.
	state.emit(_event(CG.EventKind.SUMMONED, state.tick, caster.id, new_id, action.id))

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
	return _splash_targets(state, primary, action)

## Issue 18: pulled out of `_resolve_targets` so a projectile's impact can
## gather splash around the target's *live* position at the tick it lands,
## not around whatever the primary's position was at fire time. An explosion
## should land where the shot lands.
static func _splash_targets(state: CombatState, primary: CombatUnit, action: ActionDef) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
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

	var bonus := _consume_status(state, unit, target, action)

	## How hard this hit landed, after mitigation, or 0 for a heal. Read below by
	## `_apply_status` for a status whose magnitude is the hit that applied it.
	var dealt := 0
	if action.heals:
		_apply_heal(state, unit, target, action, bonus, deps)
	else:
		dealt = _apply_damage(state, unit, target, action, bonus, deps)

	if action.applies_status_enabled:
		_apply_status(state, unit, target, action, dealt)

	_kill_if_dead(state, target, unit.id, action.id)

	if action.pull_distance > 0.0 and target.alive:
		_apply_pull(state, unit, target, action)

	if action.cleanses_harmful and target.alive:
		_cleanse_harmful(state, unit, target, action)

## The heal half. `applied` is what the health bar actually moved, so a heal on
## a target already at full emits nothing rather than a HEAL of 0.
static func _apply_heal(state: CombatState, unit: CombatUnit, target: CombatUnit, action: ActionDef, bonus: float, deps: SimDeps) -> void:
	var amount := maxi(0, int(round(deps.attack_power.call(unit, action, state.rng) + bonus)))
	var before := target.hp
	target.hp = mini(target.hp_max, target.hp + amount)
	var applied := target.hp - before
	if applied <= 0:
		return
	var e := _event(CG.EventKind.HEAL, state.tick, unit.id, target.id, action.id)
	e.amount = applied
	e.damage_type = action.damage_type
	state.emit(e)

## The damage half. Returns the MITIGATED figure, which is what a hit-scaled
## status stores -- deliberately not the `applied` figure the event carries,
## which is clamped by however much health the target had left.
static func _apply_damage(state: CombatState, unit: CombatUnit, target: CombatUnit, action: ActionDef, bonus: float, deps: SimDeps) -> int:
	var raw: float = deps.attack_power.call(unit, action, state.rng) + bonus
	var reduction: float = clampf(deps.damage_reduction.call(target), 0.0, 1.0)
	var mitigated := maxi(0, int(round(raw * (1.0 - reduction))))
	var before := target.hp
	target.hp = maxi(0, target.hp - mitigated)
	var applied := before - target.hp
	var e := _event(CG.EventKind.DAMAGE, state.tick, unit.id, target.id, action.id)
	e.amount = applied
	e.amount_before_mitigation = int(round(raw))
	## Issue 344. The middle figure, so the gap the raw roll opens can be split:
	## `amount_before_mitigation - amount_after_mitigation` was mitigated, and
	## `amount_after_mitigation - amount` was overkill on a target already dying.
	e.amount_after_mitigation = mitigated
	if mitigated < e.amount_before_mitigation:
		e.mitigation_cause = deps.damage_reduction_cause.call(target)
	e.damage_type = action.damage_type
	state.emit(e)
	_on_damage_taken(state, target, applied, deps)
	return mitigated

## The one shape a unit dies in, shared by the three things that can kill one:
static func _kill_if_dead(state: CombatState, unit: CombatUnit, source_id: int, action_id: StringName) -> bool:
	if unit.hp > 0 or not unit.alive:
		return false
	unit.alive = false
	state.emit(_event(CG.EventKind.DEATH, state.tick, source_id, unit.id, action_id))
	_kill_summons_of(state, unit)
	return true

## Issue 445: a summon dies with its summoner, on either team.
static func _kill_summons_of(state: CombatState, summoner: CombatUnit) -> void:
	var ids: Array[int] = []
	for e in state.events:
		if e.kind == CG.EventKind.SUMMONED and e.source_id == summoner.id:
			ids.append(e.target_id)
	for id in ids:
		var summon := state.unit(id)
		if summon == null or not summon.alive:
			continue
		summon.hp = 0
		_kill_if_dead(state, summon, summoner.id, &"")

# ---------------------------------------------------------------------------
# a status that remembers something (issues 121 and 130)
# ---------------------------------------------------------------------------
#
# A STATUS USED TO BE A DURATION AND NOTHING ELSE. `CombatUnit.statuses` maps a
# status to the tick it ends and there has never been anywhere to put a
# per-application payload, which is why nothing in this game stacks and why every
# damage-over-time status scaled off the same thing.

## Statuses that accumulate instead of refreshing: applying one again adds a
## stack rather than replacing what was there.
const _STACKING_STATUSES := {
	CG.Status.BLEED: true,
}

## Statuses whose magnitude is the damage of the hit that applied them.
const _HIT_SCALED_STATUSES := {
	CG.Status.BURN: true,
}

## Writes the status, its expiry and its magnitude in one place, so the three
## cannot be set inconsistently by two call sites.
static func _apply_status(state: CombatState, caster: CombatUnit, target: CombatUnit, action: ActionDef, dealt: int) -> void:
	var status: CG.Status = action.applies_status
	var carried := float(target.status_magnitude.get(status, 0.0))
	if _STACKING_STATUSES.has(status):
		target.status_magnitude[status] = carried + 1.0
	elif _HIT_SCALED_STATUSES.has(status):
		target.status_magnitude[status] = maxf(carried, float(dealt))

	target.statuses[status] = state.tick + action.status_duration_ticks
	## Latest applier wins, so a refresh re-attributes the ticks that follow it.
	target.status_source[status] = caster.id
	if status == CG.Status.TAUNTING:
		target.taunt_radius = action.taunt_radius
		_broadcast_taunt(state, target, action.status_duration_ticks)

	var se := _event(CG.EventKind.STATUS_APPLIED, state.tick, caster.id, target.id, action.id)
	se.status = status
	se.amount = int(target.status_magnitude.get(status, 0.0))
	state.emit(se)

## Strips `action.consumes_status` off the target and returns the bonus power it
## paid, or 0.0 when the action consumes nothing or the target is not carrying
## it. Every action in the game today takes the second branch.
static func _consume_status(state: CombatState, caster: CombatUnit, target: CombatUnit, action: ActionDef) -> float:
	if not action.consumes_status_enabled:
		return 0.0
	var status: CG.Status = action.consumes_status
	if not target.has_status(status):
		return 0.0
	var magnitude := float(target.status_magnitude.get(status, 0.0))
	_remove_status(target, status)
	var e := _event(CG.EventKind.STATUS_EXPIRED, state.tick, caster.id, target.id, action.id)
	e.status = status
	state.emit(e)
	return action.consumed_power_scale * magnitude

## The one place a status comes off a unit. Every erasure goes through here so
## `statuses`, `status_magnitude` and the two fields that shadow a status
## (`taunt_radius`, `sustaining`) cannot be left disagreeing -- which is exactly
## how a stale taunt radius or a phantom stack would survive a cleanse.
static func _remove_status(unit: CombatUnit, status: CG.Status) -> void:
	unit.statuses.erase(status)
	unit.status_magnitude.erase(status)
	unit.status_source.erase(status)
	if status == CG.Status.TAUNTING:
		unit.taunt_radius = 0.0
	elif status == CG.Status.SUSTAINING:
		unit.sustaining = &""
		unit.sustain_started_tick = -1

## Strips every harmful status from `target`, one STATUS_EXPIRED per removal.
static func _cleanse_harmful(state: CombatState, caster: CombatUnit, target: CombatUnit, action: ActionDef) -> void:
	if target.statuses.is_empty():
		return
	var present: Array = target.statuses.keys()
	present.sort()
	for status in present:
		if not CG.is_harmful(status):
			continue
		_remove_status(target, status)
		var e := _event(CG.EventKind.STATUS_EXPIRED, state.tick, caster.id, target.id, action.id)
		e.status = status
		state.emit(e)

## Issue 14: drags `target` toward `caster` by up to `action.pull_distance`,
## world units, over `PULL_TICKS` and stunning it for the same span.
static func _apply_pull(state: CombatState, caster: CombatUnit, target: CombatUnit, action: ActionDef) -> void:
	var to_caster := caster.position - target.position
	var dist := to_caster.length()
	if dist <= 0.0001:
		return # already on top of the caster; nothing to drag
	var travel := minf(action.pull_distance, dist)
	target.pull_step = to_caster.normalized() * (travel / float(PULL_TICKS))
	target.pull_ticks_left = PULL_TICKS
	target.statuses[CG.Status.STUN] = state.tick + PULL_TICKS
	target.status_source[CG.Status.STUN] = caster.id
	var se := _event(CG.EventKind.STATUS_APPLIED, state.tick, caster.id, target.id, action.id)
	se.status = CG.Status.STUN
	state.emit(se)

## One tick of a drag in progress, and the stun is what authorises it: a cleanse
## that frees the target of the stun also takes it off the chain.
static func _tick_pull(state: CombatState, unit: CombatUnit) -> void:
	if unit.pull_ticks_left <= 0:
		return
	if not unit.has_status(CG.Status.STUN):
		unit.pull_ticks_left = 0
		unit.pull_step = Vector2.ZERO
		return
	unit.pull_ticks_left -= 1
	unit.position = _sweep(state, unit, unit.pull_step)
	if unit.pull_ticks_left <= 0:
		unit.pull_step = Vector2.ZERO

# ---------------------------------------------------------------------------
# sustained actions
# ---------------------------------------------------------------------------
#
# A sustained action fires once and is then held: it deals its effect and
# charges `sustain_cost_per_tick` every tick, for as long as the decision
# layer keeps choosing it.
static func _begin_sustain(state: CombatState, unit: CombatUnit, action: ActionDef) -> void:
	unit.sustaining = action.id
	unit.sustain_started_tick = state.tick
	unit.statuses[CG.Status.SUSTAINING] = CG.MAX_TICKS
	state.emit(_event(CG.EventKind.SUSTAIN_START, state.tick, unit.id, -1, action.id))

## Ends it, from any of the four causes. Safe to call on a unit holding nothing,
## which is why every caller is a plain unguarded call.
static func _end_sustain(state: CombatState, unit: CombatUnit) -> void:
	if unit.sustaining == &"":
		return
	var e := _event(CG.EventKind.SUSTAIN_END, state.tick, unit.id, -1, unit.sustaining)
	e.amount = maxi(0, state.tick - unit.sustain_started_tick)
	state.emit(e)
	unit.sustaining = &""
	unit.sustain_started_tick = -1
	unit.statuses.erase(CG.Status.SUSTAINING)

## Cause (1). Called from `_decide_phase` with whatever the decision layer just
## returned, on every tick the unit was free to decide.
static func _reaffirm_sustain(state: CombatState, unit: CombatUnit, intent: Intent) -> void:
	if unit.sustaining == &"":
		return
	if intent != null and intent.kind == CG.IntentKind.USE_ACTION and intent.action_id == unit.sustaining:
		return
	_end_sustain(state, unit)

## One tick of upkeep: charge, then deal.
static func _tick_sustain(state: CombatState, unit: CombatUnit, deps: SimDeps) -> void:
	if unit.sustaining == &"":
		return
	var action: ActionDef = deps.action_lookup.call(unit.sustaining)
	if action == null or action.sustain_cost_per_tick <= 0:
		_end_sustain(state, unit)
		return
	if unit.resource < action.sustain_cost_per_tick:
		_end_sustain(state, unit)
		return

	unit.resource -= action.sustain_cost_per_tick
	var spent := _event(CG.EventKind.RESOURCE_SPENT, state.tick, unit.id, -1, action.id)
	spent.amount = action.sustain_cost_per_tick
	state.emit(spent)

	for target in _sustain_targets(state, unit, action):
		_apply_action_effect(state, unit, target, action, deps)

## Everyone inside the channel's radius this tick.
static func _sustain_targets(state: CombatState, unit: CombatUnit, action: ActionDef) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	if action.sustain_radius <= 0.0:
		return out
	var side := unit.team if action.heals else _enemy_team(unit.team)
	for other in state.living(side):
		if unit.position.distance_to(other.position) > action.sustain_radius:
			continue
		if action.requires_line_of_sight and Terrain.line_is_blocked(state.terrain, unit.position, other.position):
			continue
		out.append(other)
	return out

static func _enemy_team(team: CG.Team) -> CG.Team:
	return CG.Team.ENEMY if team == CG.Team.PLAYER else CG.Team.PLAYER

# ---------------------------------------------------------------------------
# projectiles
# ---------------------------------------------------------------------------

## Issue 18: launched instead of resolving instantly when `action.projectile_speed
## > 0.0`. `aim_point` is the target's position at this exact moment and is
## never recomputed -- no homing, which is what lets a target walk out of the
## way (it isn't there when the shot arrives) as well as walk into one early
## (`_advance_projectile`'s own hit check, below). `recover_ticks` and any
## RAGE-on-commit bookkeeping already happened in `_fire_action` before this
## is called and do not wait for impact; only the projectile's own effect
## (`_apply_action_effect`) and its RAGE-on-landed-hit gain (`_on_hit_landed`)
## are deferred to `_advance_projectile`.
static func _spawn_projectile(state: CombatState, caster: CombatUnit, target: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	var p := Projectile.new()
	p.id = state.projectiles.size()
	p.source_id = caster.id
	p.target_id = target.id
	p.action_id = action.id
	p.origin = caster.position
	p.aim_point = target.position
	p.position = caster.position
	p.speed = action.projectile_speed
	p.spawn_tick = state.tick
	state.projectiles.append(p)

## Advances every unresolved projectile by one tick and resolves the ones
## that arrive. Runs after `_tick_phase` and before `_check_outcome`, so a hit
## that would end the fight this tick still lands before the outcome is
## decided -- the same ordering guarantee every other effect in a tick
## already gets.
static func _tick_projectiles(state: CombatState, deps: SimDeps) -> void:
	var i := state.next_unresolved_projectile
	while i < state.projectiles.size():
		var p: Projectile = state.projectiles[i]
		if not p.resolved:
			_advance_projectile(state, p, deps)
		i += 1
	while state.next_unresolved_projectile < state.projectiles.size() \
			and state.projectiles[state.next_unresolved_projectile].resolved:
		state.next_unresolved_projectile += 1

## Moves `p` up to `p.speed` toward its frozen `aim_point`, then resolves it
## if either condition is met this tick:
static func _advance_projectile(state: CombatState, p: Projectile, deps: SimDeps) -> void:
	var travelled_from := p.position
	_step_projectile(p)

	var action: ActionDef = deps.action_lookup.call(p.action_id)
	var target := state.unit(p.target_id)
	var source := state.unit(p.source_id)
	if action != null and target != null and source != null:
		var shielder := _find_shielder(state, target.team, source.team, travelled_from, p.position)
		if shielder != null:
			p.resolved = true
			state.emit(_event(CG.EventKind.BLOCKED, state.tick, p.source_id, shielder.id, p.action_id))
			_land_hit(state, source, shielder, action, deps)
			return
		if _projectile_hits(state, p, target, action):
			p.resolved = true
			_land_hit(state, source, target, action, deps)
			return

	if p.position == p.aim_point:
		p.resolved = true
		state.emit(_event(CG.EventKind.MISS, state.tick, p.source_id, p.target_id, p.action_id))

## One tick of travel toward the frozen `aim_point`, landing exactly on it
## rather than overshooting -- which is what makes "reached the aim point" an
## exact equality test above rather than a distance threshold.
static func _step_projectile(p: Projectile) -> void:
	var to_aim := p.aim_point - p.position
	var remaining := to_aim.length()
	if p.speed >= remaining or remaining <= 0.0001:
		p.position = p.aim_point
	else:
		p.position = p.position + to_aim.normalized() * p.speed

## Condition (1) above: the shot's new position is inside the target's own body,
## and nothing has slid into the line since it was launched.
static func _projectile_hits(state: CombatState, p: Projectile, target: CombatUnit, action: ActionDef) -> bool:
	if not target.alive:
		return false
	if p.position.distance_to(target.position) > target.radius:
		return false
	if action.requires_line_of_sight and Terrain.line_is_blocked(state.terrain, p.position, target.position):
		return false
	return true

## What a connecting shot does, and both branches above do the same three
## things: splash around whoever it actually hit, apply the effect to each, then
## pay the source for a landed hit. `hit` is the shielder or the intended
## target; nothing else about the two branches differs.
static func _land_hit(state: CombatState, source: CombatUnit, hit: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	for t in _splash_targets(state, hit, action):
		_apply_action_effect(state, source, t, action, deps)
	_on_hit_landed(state, source, action, deps, hit.position)

## The shield's full frontage, centred on the shielder and about five pawns
## wide, so a hostile shot passing within half of it in front of a SHIELDING
## unit is taken by that unit instead of by whoever it was aimed at.
const SHIELD_WIDTH := 220.0

## A shot crossing a SHIELDING unit's front is stopped by it.
## Issue 316: would a shot from `from` to `to` be intercepted by a shield on
## `defending_team`? The plan layer's "am I in cover" question and the
## projectile's own interception must never be two implementations of it.
static func shot_would_be_shielded(state: CombatState, defending_team: CG.Team, attacking_team: CG.Team, from: Vector2, to: Vector2) -> bool:
	return _find_shielder(state, defending_team, attacking_team, from, to) != null

static func _find_shielder(state: CombatState, defending_team: CG.Team, attacking_team: CG.Team, from: Vector2, to: Vector2) -> CombatUnit:
	if attacking_team == defending_team:
		return null
	for candidate in state.living(defending_team):
		if not candidate.has_status(CG.Status.SHIELDING):
			continue
		if candidate.facing == Vector2.ZERO:
			continue # "no facing yet" per CombatUnit.facing's own doc comment: blocks nothing
		var closest := Geometry2D.get_closest_point_to_segment(candidate.position, from, to)
		if closest.distance_to(candidate.position) > SHIELD_WIDTH * 0.5:
			continue
		var to_shot := (from - candidate.position).normalized()
		if candidate.facing.dot(to_shot) <= 0.0:
			continue
		if candidate.facing.dot(to - from) < 0.0:
			return candidate
	return null

# ---------------------------------------------------------------------------
# outcome
# ---------------------------------------------------------------------------

static func _check_outcome(state: CombatState, deps: SimDeps = null) -> void:
	if deps == null:
		deps = SimDeps.new()
	var player_side := player_side_for_outcome(state)
	var enemy_side := state.living(CG.Team.ENEMY)
	var player_alive := not player_side.is_empty()
	var enemy_alive := not enemy_side.is_empty()
	var reason := CG.EndReason.NO_SURVIVORS
	if player_alive and enemy_alive:
		player_alive = _side_can_fight(state, player_side, deps)
		enemy_alive = _side_can_fight(state, enemy_side, deps)
		if not player_alive or not enemy_alive:
			reason = CG.EndReason.CANNOT_ACT

	var outcome := _outcome_for(player_alive, enemy_alive)
	if outcome == CombatState.Outcome.UNRESOLVED and state.tick >= CG.MAX_TICKS:
		outcome = CombatState.Outcome.DRAW
		reason = CG.EndReason.UNSET
	if outcome == CombatState.Outcome.UNRESOLVED:
		return
	_end_fight(state, outcome, reason)

## Who won, from who is still in the fight. UNRESOLVED means both sides are
## still standing, which is the only case the tick cap ever gets a say in.
static func _outcome_for(player_alive: bool, enemy_alive: bool) -> CombatState.Outcome:
	if player_alive and not enemy_alive:
		return CombatState.Outcome.PLAYER_WIN
	if enemy_alive and not player_alive:
		return CombatState.Outcome.ENEMY_WIN
	if not player_alive and not enemy_alive:
		return CombatState.Outcome.DRAW
	return CombatState.Outcome.UNRESOLVED

## Everything the end of a fight does, once it has been decided.
static func _end_fight(state: CombatState, outcome: CombatState.Outcome, reason: CG.EndReason) -> void:
	state.outcome = outcome
	for unit in state.units:
		if unit.alive and unit.sustaining != &"":
			_end_sustain(state, unit)
	var end_event := _event(CG.EventKind.FIGHT_END, state.tick, -1, -1, &"")
	end_event.end_reason = reason
	state.emit(end_event)

## Issue 445, and this is the only definition of "your party" in the game: a
## unit the player brought, never a summon it made.
static func is_party_member(unit: CombatUnit) -> bool:
	return unit.team == CG.Team.PLAYER and unit.pawn != null

## The player's side, for every question the outcome asks. Summons are excluded,
## so a fight is lost when the last pawn dies whatever else is still standing.
static func living_party(state: CombatState) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	for unit in state.units:
		if unit.alive and is_party_member(unit):
			out.append(unit)
	return out

## Who the outcome reads on the player's side: the living party, or every living
## player-team unit in a fight built with no pawns at all -- a test fixture or a
## level-editor room, where the pawnless rule would end the fight on tick one.
static func player_side_for_outcome(state: CombatState) -> Array[CombatUnit]:
	for unit in state.units:
		if is_party_member(unit):
			return living_party(state)
	return state.living(CG.Team.PLAYER)

static func party_was_wiped(state: CombatState) -> bool:
	var pawns := 0
	for unit in state.units:
		if not is_party_member(unit):
			continue
		pawns += 1
		if unit.alive:
			return false
	return pawns > 0

static func _side_can_fight(state: CombatState, living: Array[CombatUnit], deps: SimDeps) -> bool:
	if living.is_empty():
		return false
	for unit in living:
		if _unit_can_fight(state, unit, deps):
			return true
	return false

## Narrow on purpose. The only permanent gate in the game is
## `requires_marked_target`: a cooldown ticks down, a resource regenerates and a
## target walks back into range, so none of those may end a fight. A mark is the
## one precondition a unit cannot restore for itself, and only a living ally
## that applies MARKED can restore it.
static func _unit_can_fight(state: CombatState, unit: CombatUnit, deps: SimDeps) -> bool:
	if unit.move_speed > 0.0:
		return true
	if unit.current_action != &"" or unit.sustaining != &"":
		return true
	for p in state.projectiles:
		if not p.resolved and p.source_id == unit.id:
			return true
	var marked_only := false
	for id in unit.actions:
		var a: ActionDef = deps.action_lookup.call(id)
		if a == null:
			continue
		if not a.requires_marked_target:
			return true
		marked_only = true
	if not marked_only:
		return true
	for foe in state.living(_enemy_team(unit.team)):
		if foe.has_status(CG.Status.MARKED):
			return true
	for ally in state.living(unit.team):
		for id in ally.actions:
			var a: ActionDef = deps.action_lookup.call(id)
			if a != null and a.applies_status_enabled and a.applies_status == CG.Status.MARKED:
				return true
	return false

# ---------------------------------------------------------------------------

static func _event(kind: CG.EventKind, tick: int, source_id: int, target_id: int, action_id: StringName) -> CombatEvent:
	var e := CombatEvent.make(kind, tick)
	e.source_id = source_id
	e.target_id = target_id
	e.action_id = action_id
	return e
