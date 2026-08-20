extends "res://Tests/TestCase.gd"


## TAUNTING and SHIELDING: one mechanism serving the Warrior (guard/taunt) and
## the Siege Master (draw fire onto a summoned engine). This file covers:
##   - CombatUnit.facing, set by CombatSim from movement and from committing
##     to an action -- nothing set it before this.
##   - SHIELDING: a travelling shot crossing a shielder's front resolves
##     against the shielder instead of its intended target.
##   - TAUNTING's status machinery (apply/expire, writing taunt_radius) --
##     inert on its own; nothing yet reads it to redirect a decision. That
##     half is Scripts/Plans, routed to dace separately.

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2, actions: Array[StringName]) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.position = pos
	u.move_speed = 8.0
	u.actions = actions
	return u

func _dummy_enemy(id: int) -> CombatUnit:
	return _unit(id, CG.Team.ENEMY, 10, Vector2(100000, 100000), [])

func _idle_deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return deps

func _shot(id: StringName, speed: float, splash: float = 0.0) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 1
	a.recover_ticks = 1
	a.range_units = 999.0
	a.projectile_speed = speed
	a.splash_radius = splash
	a.damage_type = CG.DamageType.PHYSICAL
	return a

func _deps_with_action(action: ActionDef, power: float) -> SimDeps:
	var actions_by_id := {action.id: action}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _r = null) -> float: return power
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return deps

# ---------------------------------------------------------------------------
# CombatUnit.facing
# ---------------------------------------------------------------------------

func test_facing_is_set_to_the_direction_of_actual_movement() -> void:
	var deps := _idle_deps()
	var state := CombatState.new(300)
	var unit := _unit(0, CG.Team.PLAYER, 10, Vector2.ZERO, [])
	state.units.append(unit)

	unit.intent = Intent.move_to(Vector2(0, 100))
	CombatSim.step(state, deps)

	assert_almost_eq(unit.facing.x, 0.0, 0.001)
	assert_almost_eq(unit.facing.y, 1.0, 0.001, "facing must point the direction actually travelled")

func test_facing_is_unchanged_when_fully_blocked() -> void:
	var deps := _idle_deps()
	var state := CombatState.new(301)
	var unit := _unit(0, CG.Team.PLAYER, 10, Vector2.ZERO, [])
	unit.facing = Vector2(1, 0)
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	var wall := preload("res://Scripts/Core/Terrain.gd").make(
		preload("res://Scripts/Core/Terrain.gd").Kind.WALL, Rect2(Vector2(-5, -200), Vector2(10, 400)))
	state.terrain.append(wall)

	unit.intent = Intent.move_to(Vector2(100, 0)) # straight into the wall, no lateral component
	CombatSim.step(state, deps)

	assert_eq(unit.position, Vector2.ZERO, "sanity: fully blocked, must not have moved")
	assert_eq(unit.facing, Vector2(1, 0), "facing must not snap to zero on a blocked move")

func test_facing_points_toward_the_target_on_commit_and_holds_through_windup() -> void:
	var atk := _shot(&"atk", 0.0) # instant, wind_up 1
	atk.wind_up_ticks = 5
	var deps := _deps_with_action(atk, 5.0)

	var state := CombatState.new(302)
	var attacker := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 20, Vector2(0, -50), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps) # commits; facing set immediately, before the hit lands

	assert_almost_eq(attacker.facing.x, 0.0, 0.001)
	assert_almost_eq(attacker.facing.y, -1.0, 0.001, "must face the target it just committed to")

	for i in 4:
		CombatSim.step(state, deps)
		assert_almost_eq(attacker.facing.y, -1.0, 0.001, "facing must hold through the whole wind-up (tick %d)" % (i + 2))

# ---------------------------------------------------------------------------
# SHIELDING: a shot crossing a shielder's front hits the shielder instead
# ---------------------------------------------------------------------------

func test_a_shielder_facing_the_shot_intercepts_it() -> void:
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 7.0)

	var state := CombatState.new(303)
	var shooter := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var squishy := _unit(1, CG.Team.ENEMY, 30, Vector2(200, 0), [])
	var shielder := _unit(2, CG.Team.ENEMY, 50, Vector2(100, 0), [])
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.facing = Vector2(-1, 0) # facing back toward the shooter -- the shot is in front of it
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(squishy.hp, squishy.hp_max, "the intended target must be untouched -- the shot never reaches it")
	assert_eq(shielder.hp, shielder.hp_max - 7, "the shielder must take the hit instead")

func test_a_shielder_facing_away_does_not_intercept() -> void:
	# Offset off the shot's straight-line path on purpose, rather than sitting
	# on it: a shielder sitting exactly on the line is briefly "in front" of
	# the shot during the approach and briefly "behind" it during departure,
	# for *either* facing, since the half-plane test only reads the shot's
	# current position, not which way it is travelling. Offset to (100, 15),
	# the shot (moving in 20-unit ticks along y=0) grazes within the default
	# radius (22) on exactly one tick, at x=100 -- a clean single sample of
	# "am I in front of this shielder right now," not a pass-through.
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 7.0)

	var state := CombatState.new(304)
	var shooter := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var squishy := _unit(1, CG.Team.ENEMY, 30, Vector2(200, 0), [])
	var shielder := _unit(2, CG.Team.ENEMY, 50, Vector2(100, 15), [])
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.facing = Vector2(0, 1) # facing further away from the line, not back toward it
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(shielder.hp, shielder.hp_max, "a shielder facing away from its one grazing tick must not intercept")
	assert_eq(squishy.hp, squishy.hp_max - 7, "the shot must reach its intended target instead")

func test_a_shielder_out_of_its_own_radius_does_not_intercept() -> void:
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 7.0)

	var state := CombatState.new(305)
	var shooter := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var squishy := _unit(1, CG.Team.ENEMY, 30, Vector2(200, 0), [])
	var shielder := _unit(2, CG.Team.ENEMY, 50, Vector2(100, 500), []) # far off the shot's path
	shielder.radius = 22.0
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.facing = Vector2(-1, 0)
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(shielder.hp, shielder.hp_max, "a shielder far off the path must not intercept")
	assert_eq(squishy.hp, squishy.hp_max - 7, "the shot must reach its intended target instead")

func test_shielding_never_blocks_a_friendly_shot() -> void:
	var heal_shot := _shot(&"heal_shot", 20.0)
	heal_shot.heals = true
	var deps := _deps_with_action(heal_shot, 6.0)

	var state := CombatState.new(306)
	var healer := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [heal_shot.id])
	var ally := _unit(1, CG.Team.PLAYER, 10, Vector2(200, 0), [])
	ally.hp = 5 # damaged, so the heal has something to do
	var guard := _unit(2, CG.Team.PLAYER, 50, Vector2(100, 0), []) # same team as the healer
	guard.statuses[CG.Status.SHIELDING] = 999
	guard.facing = Vector2(-1, 0)
	state.units.append(healer)
	state.units.append(ally)
	state.units.append(guard)
	state.units.append(_dummy_enemy(3))

	healer.intent = Intent.use_action(heal_shot.id, ally.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(guard.hp, guard.hp_max, "a same-team guard must never intercept a friendly shot")
	assert_true(ally.hp > 5, "the heal must reach its intended ally")

func test_splash_on_a_redirected_hit_gathers_around_the_shielder() -> void:
	var shot := _shot(&"shot", 20.0, 30.0) # splash_radius 30
	var deps := _deps_with_action(shot, 6.0)

	var state := CombatState.new(307)
	var shooter := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var squishy := _unit(1, CG.Team.ENEMY, 30, Vector2(200, 0), [])
	var shielder := _unit(2, CG.Team.ENEMY, 50, Vector2(100, 0), [])
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.facing = Vector2(-1, 0)
	var behind_shielder := _unit(3, CG.Team.ENEMY, 30, Vector2(110, 0), []) # within 30 of the shielder
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)
	state.units.append(behind_shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(shielder.hp, shielder.hp_max - 6, "the shielder itself takes the hit")
	assert_eq(behind_shielder.hp, behind_shielder.hp_max - 6, "splash must gather around the shielder, not the original target")
	assert_eq(squishy.hp, squishy.hp_max, "the original target, out of splash range of the shielder, must be untouched")

# ---------------------------------------------------------------------------
# The block is observable: a BLOCKED event, and the width it is blocked at
# ---------------------------------------------------------------------------

func _events_of(state: CombatState, kind: CG.EventKind) -> Array:
	var out := []
	for e in state.events:
		if e.kind == kind:
			out.append(e)
	return out

## Three units, one shot, one interception: the event stream has to say so.
## Before this, the interception wrote nothing at all and the only way to know
## it had happened was to read hp.
func test_an_interception_emits_a_blocked_event_naming_shooter_blocker_and_action() -> void:
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 7.0)

	var state := CombatState.new(311)
	var shooter := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var squishy := _unit(1, CG.Team.ENEMY, 30, Vector2(200, 0), [])
	var shielder := _unit(2, CG.Team.ENEMY, 50, Vector2(100, 0), [])
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.facing = Vector2(-1, 0)
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	var blocked := _events_of(state, CG.EventKind.BLOCKED)
	assert_eq(blocked.size(), 1, "exactly one interception, exactly one BLOCKED event")
	var e: CombatEvent = blocked[0]
	assert_eq(e.source_id, shooter.id, "source_id is the shooter, same as DAMAGE and MISS carry")
	assert_eq(e.target_id, shielder.id, "target_id is the unit that blocked")
	assert_eq(e.action_id, shot.id, "action_id is the shot that was stopped")
	assert_eq(shielder.hp, shielder.hp_max - 7, "sanity: the block still happened")

## The negative half. A detector that fires on healthy input is worse than none,
## and this is the one a log or a floater would show constantly if it were wrong.
func test_no_blocked_event_when_nothing_intercepts() -> void:
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 7.0)

	var state := CombatState.new(312)
	var shooter := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var squishy := _unit(1, CG.Team.ENEMY, 30, Vector2(200, 0), [])
	var bystander := _unit(2, CG.Team.ENEMY, 50, Vector2(100, 500), []) # nowhere near the path
	bystander.statuses[CG.Status.SHIELDING] = 999
	bystander.facing = Vector2(-1, 0)
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(bystander)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(_events_of(state, CG.EventKind.BLOCKED).size(), 0, "an ordinary unblocked shot must emit no BLOCKED event")
	assert_eq(squishy.hp, squishy.hp_max - 7, "sanity: the shot landed on its intended target")

## The defect that made this ability mostly imaginary. Every real ranged action
## travels 65 units a tick and the shield used to be 22 wide, so a shot passing
## dead through a raised shield was sampled in front of it on one tick and
## behind it on the next, having touched the window on neither.
func test_a_shot_that_steps_clean_over_the_shielder_in_one_tick_is_still_blocked() -> void:
	var shot := _shot(&"shot", 200.0) # one tick carries it from x=0 past x=100
	var deps := _deps_with_action(shot, 7.0)

	var state := CombatState.new(313)
	var shooter := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var squishy := _unit(1, CG.Team.ENEMY, 30, Vector2(400, 0), [])
	var shielder := _unit(2, CG.Team.ENEMY, 50, Vector2(100, 0), [])
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.facing = Vector2(-1, 0)
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(_events_of(state, CG.EventKind.BLOCKED).size(), 1, "a shot faster than the shield is wide must still be caught")
	assert_eq(squishy.hp, squishy.hp_max, "the intended target must be untouched")

## The width is 40 and it is a real edge, not "everything nearby". 50 units off
## the path is outside it; the old 22 and the new 40 disagree between these two
## cases, which is what makes this pair worth having.
func test_the_shield_is_forty_wide_and_not_wider() -> void:
	var shot := _shot(&"shot", 20.0)

	var run := func(offset: float) -> Array:
		var deps := _deps_with_action(shot, 7.0)
		var state := CombatState.new(314)
		var shooter := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
		var squishy := _unit(1, CG.Team.ENEMY, 30, Vector2(200, 0), [])
		var shielder := _unit(2, CG.Team.ENEMY, 50, Vector2(100, offset), [])
		shielder.statuses[CG.Status.SHIELDING] = 999
		shielder.facing = Vector2(-1, 0)
		state.units.append(shooter)
		state.units.append(squishy)
		state.units.append(shielder)
		shooter.intent = Intent.use_action(shot.id, squishy.id)
		for i in 20:
			CombatSim.step(state, deps)
		return _events_of(state, CG.EventKind.BLOCKED)

	assert_eq((run.call(35.0) as Array).size(), 1, "35 units off the path is inside a 40-wide shield -- and outside the old 22")
	assert_eq((run.call(50.0) as Array).size(), 0, "50 units off the path is outside it: the shield is a width, not the whole room")

## A guard does not catch what has already gone past it. The front-arc test is
## asked of where the shot started its tick, so a shot leaving out the back is
## not blocked on the way out.
func test_a_shot_already_past_the_shielder_is_not_blocked_on_its_way_out() -> void:
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 7.0)

	var state := CombatState.new(315)
	# Shooter is behind the shielder's back: it faces +x, away from the shot.
	var shooter := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var squishy := _unit(1, CG.Team.ENEMY, 30, Vector2(200, 0), [])
	var shielder := _unit(2, CG.Team.ENEMY, 50, Vector2(100, 0), [])
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.facing = Vector2(1, 0) # pointing the way the shot is going: it arrives at its back
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(_events_of(state, CG.EventKind.BLOCKED).size(), 0, "a shot arriving at a shielder's back must not be blocked")
	assert_eq(squishy.hp, squishy.hp_max - 7, "it reaches its target instead")

func test_determinism_holds_with_shielding_in_play() -> void:
	var shot := _shot(&"shot", 20.0)

	var make_deps := func() -> SimDeps:
		return _deps_with_action(shot, 6.0)

	var make_state := func(seed: int) -> CombatState:
		var s := CombatState.new(seed)
		var shooter := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
		var squishy := _unit(1, CG.Team.ENEMY, 30, Vector2(200, 0), [])
		var shielder := _unit(2, CG.Team.ENEMY, 50, Vector2(100, 0), [])
		shielder.statuses[CG.Status.SHIELDING] = 999
		shielder.facing = Vector2(-1, 0)
		s.units.append(shooter)
		s.units.append(squishy)
		s.units.append(shielder)
		shooter.intent = Intent.use_action(shot.id, squishy.id)
		return s

	var state_a: CombatState = make_state.call(808)
	var state_b: CombatState = make_state.call(808)
	var deps_a: SimDeps = make_deps.call()
	var deps_b: SimDeps = make_deps.call()

	for i in 15:
		CombatSim.step(state_a, deps_a)
		CombatSim.step(state_b, deps_b)

	assert_eq(state_a.units[2].hp, state_b.units[2].hp, "same seed, same interception, same shielder hp")
	assert_eq(state_a.events.size(), state_b.events.size(), "same seed, same event count")
	for i in state_a.events.size():
		var ea: CombatEvent = state_a.events[i]
		var eb: CombatEvent = state_b.events[i]
		assert_eq(ea.kind, eb.kind, "event %d kind diverged" % i)
		assert_eq(ea.target_id, eb.target_id, "event %d target diverged" % i)
		assert_eq(ea.amount, eb.amount, "event %d amount diverged" % i)

# ---------------------------------------------------------------------------
# TAUNTING status machinery -- inert: nothing yet reads taunt_radius to
# redirect a decision. That half is Scripts/Plans, and not this file's.
# ---------------------------------------------------------------------------

func test_applying_taunting_writes_taunt_radius_onto_the_unit() -> void:
	var taunt := ActionDef.new()
	taunt.id = &"taunt"
	taunt.wind_up_ticks = 1
	taunt.recover_ticks = 1
	taunt.range_units = 999.0
	taunt.power_scale = 0.0
	taunt.applies_status_enabled = true
	taunt.applies_status = CG.Status.TAUNTING
	taunt.status_duration_ticks = 100
	taunt.taunt_radius = 250.0
	var deps := _deps_with_action(taunt, 0.0)

	var state := CombatState.new(308)
	var tank := _unit(0, CG.Team.PLAYER, 40, Vector2.ZERO, [taunt.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(50, 0), [])
	state.units.append(tank)
	state.units.append(target)

	tank.intent = Intent.use_action(taunt.id, target.id)
	CombatSim.step(state, deps)

	assert_true(target.has_status(CG.Status.TAUNTING))
	assert_eq(target.taunt_radius, 250.0, "taunt_radius must be copied from the action that applied it")

func test_taunt_radius_resets_when_taunting_expires() -> void:
	var taunt := ActionDef.new()
	taunt.id = &"taunt"
	taunt.wind_up_ticks = 1
	taunt.recover_ticks = 1
	taunt.range_units = 999.0
	taunt.power_scale = 0.0
	taunt.applies_status_enabled = true
	taunt.applies_status = CG.Status.TAUNTING
	taunt.status_duration_ticks = 2
	taunt.taunt_radius = 150.0
	var deps := _deps_with_action(taunt, 0.0)

	var state := CombatState.new(309)
	var tank := _unit(0, CG.Team.PLAYER, 40, Vector2.ZERO, [taunt.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(50, 0), [])
	state.units.append(tank)
	state.units.append(target)

	tank.intent = Intent.use_action(taunt.id, target.id)
	CombatSim.step(state, deps) # tick 1: applies, expiry set to tick 3

	assert_eq(target.taunt_radius, 150.0)

	CombatSim.step(state, deps) # tick 2: still taunted
	assert_true(target.has_status(CG.Status.TAUNTING))

	CombatSim.step(state, deps) # tick 3: expires
	assert_false(target.has_status(CG.Status.TAUNTING), "TAUNTING must actually expire")
	assert_eq(target.taunt_radius, 0.0, "taunt_radius must reset once the status is gone")

func test_reapplying_taunting_refreshes_taunt_radius() -> void:
	var weak_taunt := ActionDef.new()
	weak_taunt.id = &"weak_taunt"
	weak_taunt.wind_up_ticks = 1
	weak_taunt.recover_ticks = 1
	weak_taunt.range_units = 999.0
	weak_taunt.power_scale = 0.0
	weak_taunt.applies_status_enabled = true
	weak_taunt.applies_status = CG.Status.TAUNTING
	weak_taunt.status_duration_ticks = 100
	weak_taunt.taunt_radius = 50.0

	var strong_taunt := ActionDef.new()
	strong_taunt.id = &"strong_taunt"
	strong_taunt.wind_up_ticks = 1
	strong_taunt.recover_ticks = 1
	strong_taunt.range_units = 999.0
	strong_taunt.power_scale = 0.0
	strong_taunt.applies_status_enabled = true
	strong_taunt.applies_status = CG.Status.TAUNTING
	strong_taunt.status_duration_ticks = 100
	strong_taunt.taunt_radius = 300.0

	var actions_by_id := {weak_taunt.id: weak_taunt, strong_taunt.id: strong_taunt}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u, _a, _r = null) -> float: return 0.0
	deps.damage_reduction = func(_u) -> float: return 0.0
	deps.wind_up_ticks = func(_u, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s, _u) -> Intent: return Intent.idle()

	var state := CombatState.new(310)
	var tank_a := _unit(0, CG.Team.PLAYER, 40, Vector2.ZERO, [weak_taunt.id])
	var tank_b := _unit(1, CG.Team.PLAYER, 40, Vector2(10, 0), [strong_taunt.id])
	var target := _unit(2, CG.Team.ENEMY, 30, Vector2(50, 0), [])
	state.units.append(tank_a)
	state.units.append(tank_b)
	state.units.append(target)

	tank_a.intent = Intent.use_action(weak_taunt.id, target.id)
	CombatSim.step(state, deps)
	assert_eq(target.taunt_radius, 50.0)

	tank_b.intent = Intent.use_action(strong_taunt.id, target.id)
	CombatSim.step(state, deps)
	assert_eq(target.taunt_radius, 300.0, "a fresh application must overwrite the stored radius, same as it already overwrites the expiry tick")

# ---------------------------------------------------------------------------
# EnemyDef.spawn_taunt_radius: a non-pawn unit taunts from the moment it
# exists, since its one fixed action can never also be "taunt, then attack"
# the way a plan-driven pawn rotates between blocks.
# ---------------------------------------------------------------------------

func _engine_def(id: StringName, hp: int, taunt_radius: float) -> EnemyDef:
	var e := EnemyDef.new()
	e.id = id
	e.display_name = "Siege Engine"
	e.hp_max = hp
	e.move_speed = 0.0
	e.spawn_taunt_radius = taunt_radius
	return e

func test_an_ordinary_enemy_spawn_with_spawn_taunt_radius_is_taunting_from_build() -> void:
	var engine_def := _engine_def(&"engine", 40, 200.0)
	var encounter := Encounter.new()
	encounter.party_spawns = [Vector2(-50, 0)]
	encounter.enemy_spawns = [{"enemy_id": &"engine", "position": Vector2(50, 0)}]

	var deps := SimDeps.new()
	deps.max_hp = func(_p) -> int: return 25
	deps.max_resource = func(_p) -> int: return 10
	deps.move_speed = func(_p) -> float: return 4.0
	deps.enemy_lookup = func(id: StringName): return engine_def if id == &"engine" else null

	var pawn := preload("res://Scripts/Core/PawnData.gd").new()
	pawn.id = &"p1"
	pawn.display_name = "Test Pawn"

	var state := CombatSim.build([pawn], encounter, 400, deps)

	var engine := state.unit(1)
	assert_true(engine.has_status(CG.Status.TAUNTING), "an EnemyDef with spawn_taunt_radius > 0 must taunt from the moment build() creates it")
	assert_eq(engine.taunt_radius, 200.0)

func test_a_zero_spawn_taunt_radius_leaves_an_ordinary_enemy_untaunting() -> void:
	var engine_def := _engine_def(&"grub", 10, 0.0)
	var encounter := Encounter.new()
	encounter.party_spawns = [Vector2(-50, 0)]
	encounter.enemy_spawns = [{"enemy_id": &"grub", "position": Vector2(50, 0)}]

	var deps := SimDeps.new()
	deps.max_hp = func(_p) -> int: return 25
	deps.max_resource = func(_p) -> int: return 10
	deps.move_speed = func(_p) -> float: return 4.0
	deps.enemy_lookup = func(id: StringName): return engine_def if id == &"grub" else null

	var pawn := preload("res://Scripts/Core/PawnData.gd").new()
	pawn.id = &"p1"

	var state := CombatSim.build([pawn], encounter, 401, deps)

	assert_false(state.unit(1).has_status(CG.Status.TAUNTING), "spawn_taunt_radius 0.0 (every enemy that exists today) must not taunt")

func test_a_summoned_unit_taunts_from_spawn_too() -> void:
	var engine_def := _engine_def(&"engine", 40, 150.0)
	var build_action := ActionDef.new()
	build_action.id = &"build"
	build_action.wind_up_ticks = 1
	build_action.recover_ticks = 1
	build_action.range_units = 0.0
	build_action.summons_unit_id = &"engine"

	var actions_by_id := {build_action.id: build_action}
	var enemies_by_id := {&"engine": engine_def}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.enemy_lookup = func(id: StringName): return enemies_by_id.get(id)
	deps.attack_power = func(_u, _a, _r = null) -> float: return 0.0
	deps.damage_reduction = func(_u) -> float: return 0.0
	deps.wind_up_ticks = func(_u, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s, _u) -> Intent: return Intent.idle()

	var state := CombatState.new(402)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [build_action.id])
	state.units.append(caster)
	state.units.append(_dummy_enemy(1))

	caster.intent = Intent.use_action(build_action.id, caster.id)
	CombatSim.step(state, deps)

	var summon := state.unit(2)
	assert_not_null(summon)
	assert_true(summon.has_status(CG.Status.TAUNTING), "a summoned unit must taunt from spawn the same way an ordinary enemy spawn does")
	assert_eq(summon.taunt_radius, 150.0)
	assert_eq(summon.team, CG.Team.PLAYER, "sanity: still the caster's team, unaffected by taunting")
