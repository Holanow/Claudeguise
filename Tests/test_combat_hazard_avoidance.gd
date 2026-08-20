extends "res://Tests/TestCase.gd"


## Issue 163, the movement half: a step that would end in fire gives way to a
## clear one, when a clear one exists that still makes progress.
##
## The two that matter:
##   test_a_unit_walks_around_a_hazard_it_would_otherwise_cross  -- the defect.
##   test_a_unit_boxed_in_by_fire_still_walks_through_it         -- the limit.
##
## And `test_a_detour_never_moves_a_unit_further_from_its_destination` is the one
## guarding against a repeat of the two-tick limit cycle heron found in
## DefaultBehavior, where two branches with no hysteresis hung a fight for 2400
## ticks. Progress here is monotonic by construction and the test pins it.

func _unit(id: int, team: CG.Team, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = 200
	u.hp = 200
	u.position = pos
	u.move_speed = 10.0
	return u

func _fire(rect: Rect2, damage: int = 5):
	return Terrain.hazard(rect, damage, CG.DamageType.FIRE)

func _state(features: Array, start: Vector2 = Vector2(-100.0, 0.0)) -> CombatState:
	var state := CombatState.new(9100)
	state.terrain = features
	state.units.append(_unit(0, CG.Team.PLAYER, start))
	state.units.append(_unit(1, CG.Team.ENEMY, Vector2(5000.0, 0.0)))
	return state

func _deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.plan_decide = func(_s, _u): return null
	deps.default_decide = func(_s, _u): return Intent.idle()
	return deps

## Walks unit 0 toward `dest` for `ticks`, returning its path.
func _walk(state: CombatState, dest: Vector2, ticks: int) -> Array[Vector2]:
	var deps := _deps()
	var path: Array[Vector2] = []
	for _i in ticks:
		state.unit(0).intent = Intent.move_to(dest)
		CombatSim.step(state, deps)
		path.append(state.unit(0).position)
	return path

# ---------------------------------------------------------------------------

## THE DEFECT. Fire clipping the path, with clear ground beside it. This is the
## shape a single step can solve and it is the common one -- a unit crossing a
## room catches the corner of a hazard rather than aiming through its middle.
const _CLIPPING_FIRE := Rect2(-40.0, -60.0, 80.0, 62.0)

func test_a_unit_walks_around_a_hazard_it_would_otherwise_cross() -> void:
	var state := _state([_fire(_CLIPPING_FIRE)], Vector2(-100.0, -30.0))
	var path := _walk(state, Vector2(100.0, 10.0), 40)

	var burned := 0
	for p in path:
		if _CLIPPING_FIRE.has_point(p):
			burned += 1
	assert_eq(burned, 0, "it must not end a single tick standing in the fire")
	assert_eq(state.unit(0).hp, 200, "and therefore takes no hazard damage")

## THE LIMIT, MEASURED AND STATED RATHER THAN IMPLIED. A hazard whose whole
## width sits between a unit and its destination is still crossed. Getting round
## that needs a route -- a lane chosen several steps ahead -- and this game has
## no pathfinding and is not getting any here.
##
## Choosing a destination that is not through the fire is the DECISION layer's
## job, `Scripts/Plans`, finch's. This function only ever decides a step.
##
## Pinned as a test so nobody reads the feature as more than it is, and so the
## day somebody does build routing, this fails and tells them to delete it.
func test_a_hazard_directly_between_a_unit_and_its_goal_is_still_crossed() -> void:
	var head_on := Rect2(-40.0, -30.0, 80.0, 60.0)
	var state := _state([_fire(head_on)])
	_walk(state, Vector2(100.0, 0.0), 30)
	assert_true(state.unit(0).hp < 200,
		"a single-step rule cannot route around a wall of fire, and must not claim to")
	assert_true(state.unit(0).position.x > 40.0, "it crosses rather than stalling in front of it")

func test_the_same_walk_without_the_fire_goes_straight_through() -> void:
	var state := _state([], Vector2(-100.0, -30.0))
	var path := _walk(state, Vector2(100.0, 10.0), 40)
	var crossed := false
	for p in path:
		if _CLIPPING_FIRE.has_point(p):
			crossed = true
	assert_true(crossed, "with no hazard authored the straight line is taken, so the fixture is honest")

## THE LIMIT, stated rather than hidden: this is not pathfinding. A unit whose
## every clear step is worse off walks into the fire and burns.
func test_a_unit_boxed_in_by_fire_still_walks_through_it() -> void:
	var state := _state([_fire(Rect2(-40.0, -400.0, 80.0, 800.0))])
	_walk(state, Vector2(100.0, 0.0), 30)
	assert_true(state.unit(0).hp < 200, "a wall of fire is crossed, not solved")
	assert_true(state.unit(0).position.x > -100.0, "and it does not freeze in front of it")

## The guard against a repeat of heron's two-tick limit cycle. A detour is only
## taken when it strictly reduces the distance to the destination, so progress
## is monotonic and a unit cannot trade places between two steps forever.
func test_a_detour_never_moves_a_unit_further_from_its_destination() -> void:
	var dest := Vector2(100.0, 0.0)
	var state := _state([_fire(_CLIPPING_FIRE)])
	var path := _walk(state, dest, 40)
	var previous := dest.distance_to(Vector2(-100.0, 0.0))
	for p in path:
		var gap := dest.distance_to(p)
		assert_true(gap <= previous, "every step must close on the destination, never retreat")
		previous = gap

func test_it_still_arrives() -> void:
	var dest := Vector2(100.0, 0.0)
	var state := _state([_fire(_CLIPPING_FIRE)])
	_walk(state, dest, 60)
	assert_true(state.unit(0).position.distance_to(dest) < 15.0, "the detour is not a stall")

## A tar pit deals no damage and is still somewhere a unit would rather not be.
func test_a_status_only_hazard_is_also_avoided() -> void:
	var pit = Terrain.hazard(_CLIPPING_FIRE, 0, CG.DamageType.EARTH)
	pit.applies_status = CG.Status.SLOWED
	pit.applies_status_enabled = true
	pit.status_duration_ticks = 30
	var state := _state([pit], Vector2(-100.0, -30.0))
	_walk(state, Vector2(100.0, 10.0), 40)
	assert_false(state.unit(0).has_status(CG.Status.SLOWED), "a pit that only slows is still worth stepping around")

## A hazard authored with neither damage nor a status is decoration and must not
## deflect anybody.
func test_a_harmless_hazard_deflects_nobody() -> void:
	var state := _state([Terrain.hazard(Rect2(-40.0, -30.0, 80.0, 60.0), 0, CG.DamageType.FIRE)])
	var path := _walk(state, Vector2(100.0, 0.0), 30)
	var crossed := false
	for p in path:
		if Rect2(-40.0, -30.0, 80.0, 60.0).has_point(p):
			crossed = true
	assert_true(crossed, "decoration is not an obstacle")

## A unit that is ALREADY burning must be able to leave. Every candidate is
## judged by where it lands, so the way out is not blocked by where it started.
func test_a_unit_already_standing_in_fire_can_leave() -> void:
	var state := _state([_fire(Rect2(-40.0, -30.0, 80.0, 60.0))], Vector2.ZERO)
	_walk(state, Vector2(200.0, 0.0), 20)
	assert_true(state.unit(0).position.x > 40.0, "it got out rather than milling about inside")

## Rooms with no terrain at all -- most of the game -- take the same code path
## they always did.
func test_a_room_with_no_terrain_is_untouched() -> void:
	var state := _state([])
	_walk(state, Vector2(100.0, 0.0), 20)
	assert_almost_eq(state.unit(0).position.y, 0.0, 0.0001, "no deflection with nothing to deflect from")

func test_two_runs_from_one_seed_take_the_same_detour() -> void:
	var a := _state([_fire(_CLIPPING_FIRE)])
	var b := _state([_fire(_CLIPPING_FIRE)])
	var pa := _walk(a, Vector2(100.0, 0.0), 30)
	var pb := _walk(b, Vector2(100.0, 0.0), 30)
	assert_eq(pa, pb, "same seed, same path")
