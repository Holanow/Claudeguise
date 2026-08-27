extends "res://Tests/TestCase.gd"


## Issue 671: the four mechanisms behind the Mercenary Sellsword --
## `ActionDelivery.count`/`spread_degrees`/`homing_strength` and
## `ActionTargeting.arc_degrees` -- each defaulting to today's behaviour, and
## each exercised here in isolation from any content.

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2, actions: Array[StringName]) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.position = pos
	u.move_speed = 8.0
	# Issue 642 made reach edge-to-edge and bodies the size they are drawn, so a
	# default-radius probe overlaps every other probe and the distances written
	# in these fixtures stop meaning what they say. A point-sized body puts the
	# arithmetic back: gap == the distance in the comment.
	u.radius = 0.0
	u.actions = actions
	return u

func _shot(id: StringName, speed: float, count: int = 1, spread: float = 0.0, homing: float = 0.0) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 1
	a.recover_ticks = 1
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 999.0
	a.delivery = ActionDelivery.new()
	a.delivery.speed = speed
	a.delivery.count = count
	a.delivery.spread_degrees = spread
	a.delivery.homing_strength = homing
	var hit := HitEffect.new()
	hit.damage_type = CG.DamageType.PHYSICAL
	a.effects = [hit] as Array[AbilityEffect]
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
# count / spread_degrees
# ---------------------------------------------------------------------------

func test_count_one_spread_zero_launches_one_shot_at_the_exact_target() -> void:
	var shot := _shot(&"shot", 20.0) # count 1, spread 0.0: the defaults
	var deps := _deps_with_action(shot, 5.0)

	var state := CombatState.new(671)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps)

	assert_eq(state.projectiles.size(), 1, "count 1 must launch exactly one shot")
	assert_eq(state.projectiles[0].aim_point, Vector2(100, 0), "count 1 spread 0 must aim at the exact target position, unrotated")

func test_count_two_fans_across_spread_symmetrically() -> void:
	var shot := _shot(&"shot", 20.0, 2, 20.0) # two shots, 20 degrees apart
	var deps := _deps_with_action(shot, 5.0)

	var state := CombatState.new(672)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps)

	assert_eq(state.projectiles.size(), 2, "count 2 must launch exactly two shots")
	var a: Vector2 = state.projectiles[0].aim_point
	var b: Vector2 = state.projectiles[1].aim_point
	assert_ne(a, b, "two fanned shots must not aim at the same point")
	assert_almost_eq(a.distance_to(caster.position), target.position.distance_to(caster.position), 0.01, "fanning must not change how far a shot flies")
	assert_almost_eq(b.distance_to(caster.position), target.position.distance_to(caster.position), 0.01, "fanning must not change how far a shot flies")
	# Symmetric about the caster-to-target line: the two offsets are +-10 degrees.
	var mid := (a + b) * 0.5
	assert_almost_eq(mid.angle(), target.position.angle(), 0.05, "the fan must be centred on the original aim")

# ---------------------------------------------------------------------------
# homing_strength
# ---------------------------------------------------------------------------

func test_zero_homing_never_touches_aim_point_as_target_moves() -> void:
	var shot := _shot(&"shot", 20.0) # homing 0.0: the default
	var deps := _deps_with_action(shot, 5.0)

	var state := CombatState.new(673)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps)
	var frozen: Vector2 = state.projectiles[0].aim_point

	target.position = Vector2(100, 40)
	CombatSim.step(state, deps)

	assert_eq(state.projectiles[0].aim_point, frozen, "homing_strength 0.0 must never move the frozen aim_point")

func test_homing_turns_the_shot_toward_a_target_that_sidesteps() -> void:
	# Enough turn budget (30 deg/tick) and enough flight time to correct for a
	# sidestep that would miss a straight shot entirely.
	var shot := _shot(&"shot", 15.0, 1, 0.0, 30.0)
	var deps := _deps_with_action(shot, 6.0)

	var state := CombatState.new(674)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(150, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # launches

	target.position = Vector2(150, 60) # sidesteps well clear of the frozen aim_point

	for i in 15:
		CombatSim.step(state, deps)
		if target.hp < target.hp_max:
			break

	assert_eq(target.hp, target.hp_max - 6, "a homing shot must curve enough to land on a target that sidesteps")

func test_homing_stops_retargeting_once_the_target_is_dead() -> void:
	var shot := _shot(&"shot", 15.0, 1, 0.0, 30.0)
	var deps := _deps_with_action(shot, 6.0)

	var state := CombatState.new(675)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(150, 0), [])
	var dummy := _unit(2, CG.Team.ENEMY, 10, Vector2(100000, 100000), [])
	state.units.append(caster)
	state.units.append(target)
	state.units.append(dummy)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # launches
	var before_death: Vector2 = state.projectiles[0].aim_point

	target.hp = 0
	target.alive = false
	target.position = Vector2(150, 900) # would drag the aim wildly if still homing

	for i in 12:
		CombatSim.step(state, deps)

	assert_eq(state.projectiles[0].aim_point, before_death, "a dead target must freeze the last live aim_point, not keep dragging it")
	assert_true(state.projectiles[0].resolved, "the shot must still resolve at its frozen aim_point")

func test_homing_never_touches_state_rng() -> void:
	var shot := _shot(&"shot", 15.0, 2, 12.0, 20.0)

	var make_state := func(seed: int) -> CombatState:
		var s := CombatState.new(seed)
		var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
		var target := _unit(1, CG.Team.ENEMY, 30, Vector2(150, 0), [])
		s.units.append(caster)
		s.units.append(target)
		caster.intent = Intent.use_action(shot.id, target.id)
		return s

	var state_a: CombatState = make_state.call(909)
	var state_b: CombatState = make_state.call(909)
	var deps_a := _deps_with_action(shot, 6.0)
	var deps_b := _deps_with_action(shot, 6.0)

	for i in 15:
		state_a.units[1].position += Vector2(0, 3) # same deterministic drift on both runs
		state_b.units[1].position += Vector2(0, 3)
		CombatSim.step(state_a, deps_a)
		CombatSim.step(state_b, deps_b)

	assert_eq(state_a.units[1].hp, state_b.units[1].hp, "same seed, same drift, same outcome -- homing must not consult state.rng")
	for i in state_a.projectiles.size():
		assert_eq(state_a.projectiles[i].position, state_b.projectiles[i].position, "projectile %d position diverged" % i)

# ---------------------------------------------------------------------------
# arc_degrees
# ---------------------------------------------------------------------------

func _melee(id: StringName, splash: float, arc: float) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 1
	a.recover_ticks = 1
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 999.0
	a.targeting.splash_radius = splash
	a.targeting.arc_degrees = arc
	var hit := HitEffect.new()
	hit.damage_type = CG.DamageType.PHYSICAL
	a.effects = [hit] as Array[AbilityEffect]
	return a

func test_arc_zero_keeps_the_old_primary_centred_splash() -> void:
	var swing := _melee(&"swing", 50.0, 0.0) # arc 0.0: the default
	var deps := _deps_with_action(swing, 4.0)

	var state := CombatState.new(676)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [swing.id])
	var primary := _unit(1, CG.Team.ENEMY, 30, Vector2(40, 0), [])
	var behind_caster := _unit(2, CG.Team.ENEMY, 30, Vector2(20, 5), []) # near primary, behind the caster's swing
	caster.facing = Vector2(1, 0)
	state.units.append(caster)
	state.units.append(primary)
	state.units.append(behind_caster)

	caster.intent = Intent.use_action(swing.id, primary.id)
	CombatSim.step(state, deps)

	assert_eq(primary.hp, primary.hp_max - 4, "the primary target must be hit")
	assert_eq(behind_caster.hp, behind_caster.hp_max - 4, "arc 0.0 must keep splash centred on the primary, no facing filter")

func test_arc_hits_only_targets_within_the_casters_facing() -> void:
	var swing := _melee(&"crescent", 70.0, 60.0)
	var deps := _deps_with_action(swing, 4.0)

	var state := CombatState.new(677)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [swing.id])
	var in_front := _unit(1, CG.Team.ENEMY, 30, Vector2(40, 0), []) # dead ahead
	var behind := _unit(2, CG.Team.ENEMY, 30, Vector2(-40, 0), []) # directly behind, same distance
	caster.facing = Vector2(1, 0)
	state.units.append(caster)
	state.units.append(in_front)
	state.units.append(behind)

	caster.intent = Intent.use_action(swing.id, in_front.id)
	CombatSim.step(state, deps)

	assert_eq(in_front.hp, in_front.hp_max - 4, "a target inside the arc must be hit")
	assert_eq(behind.hp, behind.hp_max, "a target outside the arc, even in splash radius, must not be hit")

func test_arc_gathers_around_the_caster_not_the_primary() -> void:
	var swing := _melee(&"crescent", 30.0, 45.0)
	var deps := _deps_with_action(swing, 4.0)

	var state := CombatState.new(678)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [swing.id])
	var primary := _unit(1, CG.Team.ENEMY, 30, Vector2(60, 0), [])
	# 25 units from the caster (inside splash_radius 30) and dead ahead (inside
	# a 45-degree arc), but 35 units from the primary -- outside splash_radius
	# 30 measured from there. Only caster-centred gathering hits this one.
	var flank := _unit(2, CG.Team.ENEMY, 30, Vector2(25, 0), [])
	caster.facing = Vector2(1, 0)
	state.units.append(caster)
	state.units.append(primary)
	state.units.append(flank)

	caster.intent = Intent.use_action(swing.id, primary.id)
	CombatSim.step(state, deps)

	assert_eq(flank.hp, flank.hp_max - 4, "an arc action must gather splash around the CASTER, not the primary target")
