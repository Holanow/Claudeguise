extends "res://Tests/TestCase.gd"


## Issue 18: most shots become real projectiles that travel. Every action
## that exists today has projectile_speed == 0.0 (instant, unchanged); this
## file covers the mechanism a nonzero value turns on.

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

## wind_up 1, range huge: commits and fires on the very first step() call, so
## every test here can spawn a projectile with a single step and then step
## the flight by hand.
func _shot(id: StringName, speed: float, splash: float = 0.0) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 1
	a.recover_ticks = 1
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 999.0
	a.targeting.splash_radius = splash
	## Speed 0 means no delivery at all, not a delivery at 0: the second one
	## launches a shot that never arrives, which is a different fight.
	if speed > 0.0:
		a.delivery = ActionDelivery.new()
		a.delivery.speed = speed
	var hit := HitEffect.new()
	hit.damage_type = CG.DamageType.PHYSICAL
	a.effects = [hit] as Array[AbilityEffect]
	return a

func _deps_with_action(action: ActionDef, power: float, los_blocked: bool = false) -> SimDeps:
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
# a projectile action does not resolve instantly
# ---------------------------------------------------------------------------

func test_a_projectile_action_launches_instead_of_hitting_instantly() -> void:
	var shot := _shot(&"shot", 10.0)
	var deps := _deps_with_action(shot, 5.0)

	var state := CombatState.new(200)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # commits and fires this same tick (wind_up 1)

	var fired := false
	var damaged := false
	for e in state.events:
		if e.kind == CG.EventKind.ACTION_FIRE and e.source_id == 0:
			fired = true
		if e.kind == CG.EventKind.DAMAGE and e.target_id == 1:
			damaged = true

	assert_true(fired, "ACTION_FIRE still happens the tick the shot leaves")
	assert_false(damaged, "a travelling shot must not deal damage the tick it fires")
	assert_eq(state.projectiles.size(), 1, "a projectile must be launched")
	assert_eq(target.hp, target.hp_max, "target must be untouched until the shot arrives")

func test_zero_projectile_speed_still_resolves_instantly() -> void:
	# Every action that exists today. The "changes no behaviour" half.
	var atk := _shot(&"atk", 0.0)
	var deps := _deps_with_action(atk, 5.0)

	var state := CombatState.new(201)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps)

	assert_eq(state.projectiles.size(), 0, "projectile_speed 0.0 must not launch anything")
	assert_eq(target.hp, target.hp_max - 5, "must still resolve the same tick it fires, exactly as before")

# ---------------------------------------------------------------------------
# a stationary target is hit when the shot arrives
# ---------------------------------------------------------------------------

func test_a_stationary_target_is_hit_when_the_shot_arrives() -> void:
	# 100 units at 20/tick: pos 20, 40, 60, 80, 100 across ticks 1-5. The
	# default CombatUnit.radius (22) means the hit actually lands at tick 4
	# (pos 80, distance 20 <= 22), not at exact arrival -- the radius widens
	# the window, which is the point of using it instead of a point check.
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 7.0)

	var state := CombatState.new(202)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # tick 1: launches, and takes its first tick of travel (pos 20)

	# Ticks 2-3: still travelling (pos 40, 60), both outside the 22-unit
	# radius (distance 60 and 40).
	for i in 2:
		CombatSim.step(state, deps)
		assert_eq(target.hp, target.hp_max, "must not connect before the travel time elapses (tick %d)" % (i + 2))

	CombatSim.step(state, deps) # tick 4: pos 80, distance 20 <= radius 22 -- connects

	assert_eq(target.hp, target.hp_max - 7, "must connect once the shot is within the target's radius")
	assert_true(state.projectiles[0].resolved)

# ---------------------------------------------------------------------------
# a target can move out of the way -- no homing
# ---------------------------------------------------------------------------

func test_a_target_that_moves_away_is_missed_not_chased() -> void:
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 7.0)

	var state := CombatState.new(203)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # launches, aim_point frozen at (100, 0)

	target.position = Vector2(100, 500) # steps out of the shot's path entirely

	for i in 10:
		CombatSim.step(state, deps)

	assert_eq(target.hp, target.hp_max, "a target that moved away must not be hit")
	assert_true(state.projectiles[0].resolved, "the shot must still resolve (as a miss) at its aim_point")

	var miss_count := 0
	for e in state.events:
		if e.kind == CG.EventKind.MISS and e.source_id == 0:
			miss_count += 1
	assert_eq(miss_count, 1, "a shot that reaches an empty aim_point must emit exactly one MISS")

# ---------------------------------------------------------------------------
# a target can walk into an incoming shot early
# ---------------------------------------------------------------------------

func test_a_target_that_walks_into_the_shot_is_hit_early() -> void:
	# Speed kept below the target's default radius (22) on purpose: the hit
	# check only runs once per tick, at the projectile's post-move position,
	# so a per-tick step no bigger than the target's own radius guarantees a
	# stationary target standing at the projectile's *previous* position is
	# still within range of its *new* one -- no continuous-sweep collision
	# needed, same coarseness the rest of this file already accepts.
	var shot := _shot(&"shot", 10.0)
	var deps := _deps_with_action(shot, 9.0)

	var state := CombatState.new(204)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # launches and takes its first tick of travel
	CombatSim.step(state, deps) # a second tick of travel

	# Walk the target onto the projectile's current position, well short of
	# the aim_point at (100, 0) -- if this only worked via homing, the shot
	# would never reach here since aim_point never moves.
	target.position = state.projectiles[0].position

	CombatSim.step(state, deps) # the next advance should find the target already there

	assert_eq(target.hp, target.hp_max - 9, "walking into the shot's path must land it early")
	assert_true(state.projectiles[0].resolved)

# ---------------------------------------------------------------------------
# hit radius is the target's own CombatUnit.radius -- no invented constant
# ---------------------------------------------------------------------------

func test_a_large_radius_target_is_hit_even_off_the_exact_aim_point() -> void:
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 5.0)

	var state := CombatState.new(205)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	target.radius = 50.0
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # launches; aim_point frozen at (100, 0)
	target.position = Vector2(100, 40) # drifts 40 units off the aim_point, within its own 50-radius

	for i in 10:
		CombatSim.step(state, deps)

	assert_eq(target.hp, target.hp_max - 5, "a wide-radius target off the exact aim_point must still be hit")

func test_a_small_radius_target_just_outside_it_is_missed() -> void:
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 5.0)

	var state := CombatState.new(210)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	target.radius = 5.0
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # launches; aim_point frozen at (100, 0)
	target.position = Vector2(100, 40) # same 40-unit drift, now outside its own 5-radius

	for i in 10:
		CombatSim.step(state, deps)

	assert_eq(target.hp, target.hp_max, "a narrow-radius target that drifted outside it must not be hit")
	assert_true(state.projectiles[0].resolved, "must still resolve as a miss, not fly forever")

# ---------------------------------------------------------------------------
# a dead target before impact is an ordinary miss, no special case
# ---------------------------------------------------------------------------

func test_a_target_that_dies_before_impact_is_missed() -> void:
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 7.0)

	var state := CombatState.new(206)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	# Killing `target` below must not also end the fight -- if it were the
	# only enemy, the next _check_outcome would resolve PLAYER_WIN and every
	# later step() would no-op, freezing the in-flight projectile along with
	# everything else and making this scenario untestable in isolation. A
	# second, harmless enemy keeps the fight UNRESOLVED.
	state.units.append(caster)
	state.units.append(target)
	state.units.append(_dummy_enemy(2))

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # launches

	target.hp = 0
	target.alive = false

	for i in 10:
		CombatSim.step(state, deps)

	assert_true(state.projectiles[0].resolved, "must still resolve even though the target died first")
	var damaged := false
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE and e.target_id == 1 and e.tick > 1:
			damaged = true
	assert_false(damaged, "a dead target must not take a second, posthumous hit from the shot")

# ---------------------------------------------------------------------------
# a dead source needs no special case -- everything was captured at launch
# ---------------------------------------------------------------------------

func test_the_shot_still_lands_if_the_source_dies_mid_flight() -> void:
	var shot := _shot(&"shot", 20.0)
	var deps := _deps_with_action(shot, 7.0)

	var state := CombatState.new(207)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	# Same reasoning as the target-dies test above, mirrored for the other
	# side: killing `caster` below must not itself end the fight (ENEMY_WIN),
	# which would freeze the in-flight projectile via step()'s own early
	# return and make "the shot still lands" untestable. A second, harmless
	# ally keeps the fight UNRESOLVED.
	var ally := _unit(2, CG.Team.PLAYER, 20, Vector2(-100000, -100000), [])
	state.units.append(caster)
	state.units.append(target)
	state.units.append(ally)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # launches

	caster.hp = 0
	caster.alive = false

	for i in 10:
		CombatSim.step(state, deps)

	assert_eq(target.hp, target.hp_max - 7, "an already-loosed shot must land even if its source is now dead")

# ---------------------------------------------------------------------------
# splash gathers around the target's position at impact, not at fire time
# ---------------------------------------------------------------------------

func test_splash_gathers_at_impact_around_the_targets_live_position() -> void:
	var shot := _shot(&"shot", 20.0, 30.0) # splash_radius 30
	var deps := _deps_with_action(shot, 6.0)

	var state := CombatState.new(208)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	# Starts far outside splash range of the aim_point; walks into range
	# before impact. If splash were still gathered at fire time (the old
	# instant-action behaviour) this ally would never be hit.
	var ally := _unit(2, CG.Team.ENEMY, 30, Vector2(500, 500), [])
	state.units.append(caster)
	state.units.append(target)
	state.units.append(ally)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # launches

	ally.position = Vector2(110, 0) # now well within 30 units of the target

	for i in 10:
		CombatSim.step(state, deps)

	assert_eq(target.hp, target.hp_max - 6, "the primary target must still be hit")
	assert_eq(ally.hp, ally.hp_max - 6, "splash must gather around the target's position at impact, not at fire time")

# ---------------------------------------------------------------------------
# determinism holds with travel in play
# ---------------------------------------------------------------------------

func test_determinism_holds_with_projectiles_in_play() -> void:
	var shot := _shot(&"shot", 15.0)

	var make_deps := func() -> SimDeps:
		return _deps_with_action(shot, 8.0)

	var make_state := func(seed: int) -> CombatState:
		var s := CombatState.new(seed)
		var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
		var target := _unit(1, CG.Team.ENEMY, 30, Vector2(140, 0), [])
		s.units.append(caster)
		s.units.append(target)
		caster.intent = Intent.use_action(shot.id, target.id)
		return s

	var state_a: CombatState = make_state.call(909)
	var state_b: CombatState = make_state.call(909)
	var deps_a: SimDeps = make_deps.call()
	var deps_b: SimDeps = make_deps.call()

	for i in 15:
		CombatSim.step(state_a, deps_a)
		CombatSim.step(state_b, deps_b)

	assert_eq(state_a.units[1].hp, state_b.units[1].hp, "same seed, same shot, same landed hp")
	assert_eq(state_a.projectiles.size(), state_b.projectiles.size())
	for i in state_a.projectiles.size():
		assert_eq(state_a.projectiles[i].position, state_b.projectiles[i].position, "projectile %d position diverged" % i)
		assert_eq(state_a.projectiles[i].resolved, state_b.projectiles[i].resolved, "projectile %d resolved-state diverged" % i)

	assert_eq(state_a.events.size(), state_b.events.size(), "same seed, same event count")
	for i in state_a.events.size():
		var ea: CombatEvent = state_a.events[i]
		var eb: CombatEvent = state_b.events[i]
		assert_eq(ea.kind, eb.kind, "event %d kind diverged" % i)
		assert_eq(ea.tick, eb.tick, "event %d tick diverged" % i)
		assert_eq(ea.amount, eb.amount, "event %d amount diverged" % i)

# ---------------------------------------------------------------------------
# line of sight is re-checked per tick, not only at fire time
# ---------------------------------------------------------------------------

func test_line_of_sight_is_rechecked_every_tick_the_shot_travels() -> void:
	var shot := _shot(&"shot", 20.0)
	shot.targeting.requires_line_of_sight = true
	var deps := _deps_with_action(shot, 9.0)

	var state := CombatState.new(209)
	# No wall yet at fire time -- the shot must be free to launch.
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [shot.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(shot.id, target.id)
	CombatSim.step(state, deps) # launches with a clear line

	# A wall slides in after launch, covering the target's own position (and
	# therefore the aim_point too, since the target hasn't moved) -- this
	# guarantees the LOS check is what blocks the hit specifically, rather
	# than the shot merely running out of range before reaching the wall's
	# x-extent, which "in range but blocked" needs to isolate.
	state.terrain.append(Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(85, -50), Vector2(30, 100))))

	for i in 10:
		CombatSim.step(state, deps)

	assert_eq(target.hp, target.hp_max, "a wall blocking the path after launch must still stop the shot")
	assert_true(state.projectiles[0].resolved, "the shot must still resolve (as a miss) rather than fly forever")
