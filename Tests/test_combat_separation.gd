extends "res://Tests/TestCase.gd"


## Issue 642, `CombatSim._separate_phase`. Nothing in the simulation had ever
## compared one unit's position to another's, so these assert the mechanism
## rather than its effect on a fight.

## `move_speed` 0 and an idle decider, so the only thing that can move a body
## in these fixtures is separation.
func _unit(id: int, team: CG.Team, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = 1000
	u.hp = 1000
	u.position = pos
	u.move_speed = 0.0
	return u

func _idle_deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return deps

## Two player bodies and one enemy parked far away, because a state with an
## empty team resolves on its first step and never runs a second one.
func _pair(a_at: Vector2, b_at: Vector2) -> CombatState:
	var state := CombatState.new(7)
	state.units.append(_unit(0, CG.Team.PLAYER, a_at))
	state.units.append(_unit(1, CG.Team.PLAYER, b_at))
	state.units.append(_unit(2, CG.Team.ENEMY, Vector2(4000.0, 4000.0)))
	return state


func test_two_overlapping_bodies_end_up_clear_of_each_other() -> void:
	var state := _pair(Vector2(-5.0, 0.0), Vector2(5.0, 0.0))
	var deps := _idle_deps()
	var a := state.unit(0)
	var b := state.unit(1)
	assert_true(a.gap(b) < 0.0, "the fixture must start overlapped, or this proves nothing")
	for _i in 40:
		CombatSim.step(state, deps)
	assert_true(a.gap(b) >= -0.01,
		"two bodies must not stand inside each other, gap is %.2f" % a.gap(b))

## The negative half. A detector that fires on healthy input becomes furniture,
## and the same is true of a phase that moves bodies nobody asked it to move.
func test_bodies_already_clear_of_each_other_are_never_moved() -> void:
	var state := _pair(Vector2(-200.0, 0.0), Vector2(200.0, 0.0))
	var deps := _idle_deps()
	for _i in 20:
		CombatSim.step(state, deps)
	assert_eq(state.unit(0).position, Vector2(-200.0, 0.0), "a body nothing is touching must not move")
	assert_eq(state.unit(1).position, Vector2(200.0, 0.0), "and neither must the other one")

## Exactly coincident is the case with no direction to push along, which is
## every summon on the tick it is built.
func test_exactly_coincident_bodies_separate_the_same_way_every_run() -> void:
	var first: Array[Vector2] = []
	var second: Array[Vector2] = []
	for run in 2:
		var state := _pair(Vector2.ZERO, Vector2.ZERO)
		var deps := _idle_deps()
		for _i in 40:
			CombatSim.step(state, deps)
		var into: Array[Vector2] = first if run == 0 else second
		into.append(state.unit(0).position)
		into.append(state.unit(1).position)
	assert_eq(first, second, "the same fixture must separate the same bodies the same way")
	assert_true(first[0].distance_to(first[1]) > 0.0, "coincident bodies must actually come apart")

## Separation walks its push through `_sweep`, so it obeys the same terrain
## rule movement does. Without that it is the one thing in the simulation that
## can post a body inside a wall.
func test_a_push_never_lands_a_body_inside_terrain() -> void:
	var state := _pair(Vector2(-40.0, 0.0), Vector2(-30.0, 0.0))
	state.grid.stamp_features([Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(-400.0, -200.0), Vector2(300.0, 400.0)))])
	var deps := _idle_deps()
	var pushed := state.unit(0)
	assert_false(state.grid.move_blocked(pushed.position, pushed.radius), "the fixture must start clear of the wall")
	var started_at := pushed.position
	for _i in 40:
		CombatSim.step(state, deps)
		assert_false(state.grid.move_blocked(pushed.position, pushed.radius),
			"separation pushed a body into the wall at %s" % pushed.position)
	assert_true(pushed.position.x < started_at.x - 0.01,
		"nothing pushed this body toward the wall, so staying out of it proves nothing")
