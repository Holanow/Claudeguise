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
const Projectile := preload("res://Scripts/Core/Projectile.gd")
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
	_tick_projectiles(state, deps)
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
	## EnemyDef.spawn_taunt_radius's own doc comment: a non-pawn unit's action
	## list only ever runs one fixed action, so it cannot rotate between
	## "taunt" and "attack" the way a plan-driven pawn can -- a summoned siege
	## engine that needs to draw fire gets TAUNTING applied here, at spawn,
	## rather than through an action it would then never be able to also
	## attack with. CG.MAX_TICKS as the expiry is "outlives the fight" -- a
	## fight cannot run longer than that tick, so this never has to be
	## refreshed or read as having expired mid-fight. Shared by both call
	## sites of _build_enemy_unit (an ordinary encounter spawn in build() and
	## a mid-fight _spawn_summon), on purpose: content decides via the
	## EnemyDef, not via which path built the unit.
	if enemy_def.spawn_taunt_radius > 0.0:
		u.statuses[CG.Status.TAUNTING] = CG.MAX_TICKS
		u.taunt_radius = enemy_def.spawn_taunt_radius
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
				_resolve_move(state, unit, intent, deps)
			CG.IntentKind.USE_ACTION:
				_resolve_use_action(state, unit, intent, deps)
			_:
				pass

## No pathfinding: a unit that cannot take its full step tries sliding along
## one axis at a time, and stays put only if neither axis is clear either.
## Enough for a room built from a few rectangles, per issue 13a's own scope;
## a unit that genuinely cannot route around an obstacle is a finding to
## report, not a pathfinder to build.
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
		unit.position = direct
		_update_facing_from_movement(unit, before)
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
##
## Deliberately the only place `unit.move_speed` gets touched for movement.
## `unit.move_speed` itself is set once in build() from deps.move_speed and
## never mutated -- SLOWED is a per-tick read-time multiplier, not a write to
## the unit, which is what lets it expire cleanly with nothing to restore.
static func _effective_move_speed(unit: CombatUnit, deps: SimDeps) -> float:
	if not unit.has_status(CG.Status.SLOWED):
		return unit.move_speed
	var scale: float = deps.slowed_speed_scale.call(unit)
	return maxf(0.0, unit.move_speed * scale)

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
	_update_facing_toward(state, unit, intent.target_id)
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
			## TAUNTING is the first status with a stored magnitude
			## (taunt_radius) rather than a pure read-while-present multiplier
			## like SLOWED/HASTE -- reset it so nothing downstream can read a
			## stale radius off a unit that no longer carries the status.
			if status == CG.Status.TAUNTING:
				unit.taunt_radius = 0.0
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

	if action.summons_unit_id != &"":
		_spawn_summon(state, unit, action, deps)

	var targets := _resolve_targets(state, unit, action)
	if targets.is_empty():
		state.emit(_event(CG.EventKind.MISS, state.tick, unit.id, unit.focus_id, action.id))
	elif action.projectile_speed > 0.0:
		## Issue 18: range and line-of-sight are still checked right here, at
		## the moment the wind-up completes, exactly as an instant action --
		## an out-of-range or blocked target still MISSes immediately above,
		## nothing launches. The only change for a target that IS resolved:
		## the effect does not land yet. `_spawn_projectile` aims at
		## `targets[0]` (the primary) only; splash, if any, is regathered
		## around the target's live position at impact, not fire time -- see
		## `_splash_targets`'s own doc comment.
		_spawn_projectile(state, unit, targets[0], action, deps)
	else:
		for target in targets:
			_apply_action_effect(state, unit, target, action, deps)
		if not targets.is_empty():
			_on_hit_landed(state, unit, deps)

	unit.current_action = action.id
	unit.action_ticks_left = 0
	unit.recover_ticks_left = _apply_haste(unit, deps, int(deps.recover_ticks.call(unit, action)))
	if action.cooldown_ticks > 0:
		unit.cooldowns[action.id] = state.tick + action.cooldown_ticks
	if unit.recover_ticks_left <= 0:
		unit.current_action = &""

## Rage gains only from a landed hit, not from committing or from a miss: a
## Rage pawn swinging at nothing (out of range at landing) must not fill, per
## issue 4's own acceptance criterion for it. Issue 18 split this out of
## `_fire_action` because "landed" now happens at two different moments: the
## same tick as firing for an instant action, or a later tick at projectile
## impact -- `_advance_projectile` calls this too, once it resolves a hit.
static func _on_hit_landed(state: CombatState, source: CombatUnit, deps: SimDeps) -> void:
	if source.resource_kind != CG.ResourceKind.RAGE:
		return
	var gained := _stochastic_round(state, deps.rage_gain_on_attack.call(source))
	if gained > 0:
		source.resource = clampi(source.resource + gained, 0, source.resource_max)

## Issue 12: the one place `state.units` grows after `build()`. Appends only --
## never inserts, never reorders -- so a new unit's id is `state.units.size()`
## at the moment it is appended, which is exactly the index `state.unit(id)`
## expects. Every existing id keeps pointing at the same unit forever, same as
## before this existed.
##
## Runs unconditionally when the action fires, independent of whether
## `_resolve_targets` finds anything: a build action is not an attack, and
## content is free to give it no target at all (or a self-target) without the
## summon becoming contingent on a hit.
##
## Deterministic by construction: no rng, no wall-clock, nothing but the
## caster's own state and `deps.enemy_lookup`, which is a pure content lookup.
## Same seed, same decisions, same casters resolve in the same tick in the
## same order (CombatState's own ordering rule -- iterate `units`, never a
## Dictionary), so two runs from the same seed spawn identically. Unknown
## `EnemyDef` ids are handled by `_build_enemy_unit` itself, the same way an
## unknown enemy spawn in `build()` already is.
##
## Spawned on the caster's team, at the caster's exact position ("at or near"
## per issue 12) -- units do not collide with each other, only with terrain, so
## sharing a point is not a stuck state.
##
## A unit appended here can be visited later in the same tick's `_resolve_phase`
## or `_tick_phase` loop, because both iterate `state.units` directly and Array
## iteration in GDScript re-reads size() each step. That is harmless rather
## than avoided: a unit that did not exist during `_decide_phase` has
## `intent == null` and `action_ticks_left == 0` / `recover_ticks_left == 0`, so
## every branch that would touch it this tick is a no-op. It gets its first
## real decision on the following tick, same as any unit built in `build()`
## would if `_decide_phase` had not already run for tick 1.
static func _spawn_summon(state: CombatState, caster: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	var enemy_def: EnemyDef = deps.enemy_lookup.call(action.summons_unit_id)
	var new_id := state.units.size()
	var summon := _build_enemy_unit(new_id, enemy_def, action.summons_unit_id, caster.position, caster.team)
	state.units.append(summon)

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
		## TAUNTING's reach is stored on the taunting unit itself rather than
		## re-derived from its action list each tick -- ActionDef.taunt_radius's
		## own doc comment. Reapplying (a refresh) overwrites it the same way
		## reapplying any other status already overwrites its expiry tick.
		if action.applies_status == CG.Status.TAUNTING:
			target.taunt_radius = action.taunt_radius
		var se := _event(CG.EventKind.STATUS_APPLIED, state.tick, unit.id, target.id, action.id)
		se.status = action.applies_status
		state.emit(se)

	if target.hp <= 0 and target.alive:
		target.alive = false
		state.emit(_event(CG.EventKind.DEATH, state.tick, unit.id, target.id, action.id))

	if action.pull_distance > 0.0 and target.alive:
		_apply_pull(state, unit, target, action.pull_distance)

## Issue 14: drags `target` toward `caster` by up to `distance`, world units.
## Guarded by the caller on `target.alive` -- checked *after* this same
## effect's own damage/death resolution above, so a pull on a killing blow
## never fires on a corpse.
##
## Reuses `_sweep`, the same increment-and-stop walk ordinary movement already
## uses against `Terrain.point_is_blocked`, rather than a straight-line
## teleport: a pull that can shove a unit through a wall is exactly the "lands
## inside terrain" failure issue 14 names, and `_sweep` already refuses to
## land past the first blocked increment. A pull that meets a wall stops at
## the wall instead of failing outright -- dragged as far as the wall allows,
## which reads better than a hook that does nothing because the last few units
## of it were blocked.
static func _apply_pull(state: CombatState, caster: CombatUnit, target: CombatUnit, distance: float) -> void:
	var to_caster := caster.position - target.position
	var dist := to_caster.length()
	if dist <= 0.0001:
		return # already on top of the caster; nothing to drag
	var travel := minf(distance, dist)
	var step := to_caster.normalized() * travel
	target.position = _sweep(state, target, step)

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
##
## Scans from `state.next_unresolved_projectile` rather than 0: resolved
## entries stay in the array in place (same "dead units stay in place"
## convention `state.units` already uses -- nothing iterating mid-tick should
## see the array reshuffle), and a long, hasted fight can accumulate
## thousands of them. Correctness never depends on the cursor: the scan below
## still covers cursor..end in full every tick, so a fast projectile launched
## after a slower one is still found and resolved even though it isn't at the
## front. The cursor only buys speed, on the assumption that resolution is
## *roughly* in launch order -- if that assumption turns out false in
## practice, this degrades toward scanning the same already-resolved prefix
## repeatedly, not toward missing anything.
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
##
## 1. Its target is still alive and `p`'s new position is within the
##    target's own `radius` of the target's *current* position -- reusing
##    the field the movement code already treats as a unit's physical size
##    rather than inventing a second "how close counts as a hit" number.
##    This is what lets a target walk into an incoming shot early.
## 2. It has reached `aim_point` without (1) firing -- resolves as an
##    ordinary MISS, the same event an out-of-range shot already gets today.
##    This is what lets a target walk out of the way: nothing is at the aim
##    point anymore.
##
## A target that died before impact simply never satisfies (1) again (`state.unit`
## still resolves the id -- ids are stable forever -- but `.alive` is false),
## so it falls through to (2), an ordinary miss, with no cancellation path to
## build. A dead source needs nothing special at all: everything this needs
## (`source_id`, `target_id`, `action_id`, `aim_point`) was captured at launch.
##
## `requires_line_of_sight` is re-checked every tick against the live
## predicate (`Terrain.line_is_blocked`, projectile's current position to the
## target's current position) rather than once at fire time, so a pillar
## sliding into the path blocks that tick's hit-check with no special case.
static func _advance_projectile(state: CombatState, p: Projectile, deps: SimDeps) -> void:
	var to_aim := p.aim_point - p.position
	var remaining := to_aim.length()
	if p.speed >= remaining or remaining <= 0.0001:
		p.position = p.aim_point
	else:
		p.position = p.position + to_aim.normalized() * p.speed

	var action: ActionDef = deps.action_lookup.call(p.action_id)
	var target := state.unit(p.target_id)
	var source := state.unit(p.source_id)
	if action != null and target != null and source != null:
		## SHIELDING checked before the intended target, every tick the shot
		## is in flight -- a shielder standing between the shooter and the
		## target intercepts it wherever the shot currently is, not only once
		## it would have reached the original target. Checked even if `target`
		## has already died: the guard reacts to a hostile shot crossing its
		## front regardless of what the shot was originally aimed at.
		var shielder := _find_shielder(state, target.team, source.team, p.position)
		if shielder != null:
			p.resolved = true
			for t in _splash_targets(state, shielder, action):
				_apply_action_effect(state, source, t, action, deps)
			_on_hit_landed(state, source, deps)
			return

		if target.alive:
			var in_range := p.position.distance_to(target.position) <= target.radius
			var blocked := action.requires_line_of_sight \
				and Terrain.line_is_blocked(state.terrain, p.position, target.position)
			if in_range and not blocked:
				p.resolved = true
				for t in _splash_targets(state, target, action):
					_apply_action_effect(state, source, t, action, deps)
				_on_hit_landed(state, source, deps)
				return

	if p.position == p.aim_point:
		p.resolved = true
		state.emit(_event(CG.EventKind.MISS, state.tick, p.source_id, p.target_id, p.action_id))

## A shot crossing a SHIELDING unit's front is stopped by it, per
## CG.Status.SHIELDING's own doc comment -- this is the projectile-based
## design that comment named as the point of building #18 first, replacing
## the geometric-line-check fallback it also named (never built, since
## projectiles landed before this did).
##
## Front-arc test is a plain half-plane: `facing.dot(to_shot) > 0`. Zero
## invented constants -- a dot-product sign test already means "generally in
## front, not behind," same instinct as reusing `radius` for the ordinary hit
## check rather than inventing a second number for "how close counts."
##
## `attacking_team == defending_team` returns null immediately, so a shield
## never blocks a friendly heal or buff aimed at an ally standing behind it --
## SHIELDING stops incoming fire, not outgoing support.
##
## First qualifying shielder in `state.living(defending_team)` order wins,
## same "iterate units, never a Dictionary" determinism rule every other
## tie-break in this file already follows.
static func _find_shielder(state: CombatState, defending_team: CG.Team, attacking_team: CG.Team, position: Vector2) -> CombatUnit:
	if attacking_team == defending_team:
		return null
	for candidate in state.living(defending_team):
		if not candidate.has_status(CG.Status.SHIELDING):
			continue
		if candidate.facing == Vector2.ZERO:
			continue # "no facing yet" per CombatUnit.facing's own doc comment: blocks nothing
		if position.distance_to(candidate.position) > candidate.radius:
			continue
		## Vector2.normalized() on a zero-length vector returns ZERO rather
		## than dividing by zero, so a shot landing exactly on the shielder's
		## own position dots to 0 and correctly falls through to "not in
		## front" rather than special-casing "can't be behind me if it's
		## exactly on me" -- a shot dead-centre on a shielder facing away is
		## still approaching from the shielder's back, not its front.
		var to_shot := (position - candidate.position).normalized()
		if candidate.facing.dot(to_shot) > 0.0:
			return candidate
	return null

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
