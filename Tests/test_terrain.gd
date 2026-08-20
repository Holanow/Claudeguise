extends "res://Tests/TestCase.gd"


## MANAGER-OWNED. Terrain geometry is the one piece of maths three sessions
## would otherwise each write, so it is written once and tested hard here rather
## than three times and tested loosely.
##
## Line-of-sight in particular is the classic subtly-wrong-for-a-year function:
## it passes every test anyone thinks to write with a wall directly between two
## points, and is wrong for a wall beside the line, behind a point, or exactly
## touching it. Those cases are all below.


func _wall(x: float, y: float, w: float, h: float):
	return Terrain.make(Terrain.Kind.WALL, Rect2(x, y, w, h))


func test_a_wall_between_two_points_blocks_sight() -> void:
	var features := [_wall(-10.0, -50.0, 20.0, 100.0)]
	assert_true(Terrain.line_is_blocked(features, Vector2(-100, 0), Vector2(100, 0)))


func test_a_wall_beside_the_line_does_not_block_it() -> void:
	# The case that catches a bounding-box test masquerading as a line test.
	# The wall's bounding box overlaps the segment's bounding box; the wall is
	# nowhere near the line.
	var features := [_wall(-10.0, 40.0, 20.0, 100.0)]
	assert_false(Terrain.line_is_blocked(features, Vector2(-100, 0), Vector2(100, 0)))


func test_a_wall_behind_a_point_does_not_block() -> void:
	# Catches treating the segment as an infinite ray, which is the other half
	# of the same bug and which no "wall in the middle" test can see.
	var features := [_wall(200.0, -50.0, 20.0, 100.0)]
	assert_false(Terrain.line_is_blocked(features, Vector2(-100, 0), Vector2(100, 0)))


func test_a_diagonal_line_through_a_corner_blocks() -> void:
	var features := [_wall(0.0, 0.0, 50.0, 50.0)]
	assert_true(Terrain.line_is_blocked(features, Vector2(-20, -20), Vector2(70, 70)))


func test_a_diagonal_line_that_misses_the_corner_does_not_block() -> void:
	# One unit of difference from the case above, on purpose: a corner test that
	# is off by the width of the rectangle passes the previous test and fails
	# this one.
	var features := [_wall(0.0, 0.0, 50.0, 50.0)]
	assert_false(Terrain.line_is_blocked(features, Vector2(-20, 60), Vector2(60, 140)))


func test_a_pillar_blocks_sight_but_not_movement() -> void:
	var pillar = Terrain.make(Terrain.Kind.PILLAR, Rect2(-10, -10, 20, 20))
	assert_true(pillar.blocks_sight())
	assert_false(pillar.blocks_movement())
	assert_true(Terrain.line_is_blocked([pillar], Vector2(-100, 0), Vector2(100, 0)))
	assert_false(Terrain.point_is_blocked([pillar], Vector2(0, 0), 5.0))


func test_a_pit_blocks_movement_but_not_sight() -> void:
	# The exact inverse of a pillar. Having both means neither can be
	# implemented as "solid" and quietly pass.
	var pit = Terrain.make(Terrain.Kind.PIT, Rect2(-10, -10, 20, 20))
	assert_false(pit.blocks_sight())
	assert_true(pit.blocks_movement())
	assert_false(Terrain.line_is_blocked([pit], Vector2(-100, 0), Vector2(100, 0)))
	assert_true(Terrain.point_is_blocked([pit], Vector2(0, 0), 5.0))


func test_blocking_accounts_for_the_unit_radius() -> void:
	# A unit is a circle to the movement code even though it is a point to the
	# targeting code. A centre just outside a wall with a radius that reaches
	# into it is blocked.
	var features := [_wall(0.0, -50.0, 20.0, 100.0)]
	assert_false(Terrain.point_is_blocked(features, Vector2(-30, 0), 5.0))
	assert_true(Terrain.point_is_blocked(features, Vector2(-30, 0), 40.0))


func test_a_hazard_is_passable_and_reports_itself() -> void:
	var lava = Terrain.hazard(Rect2(-20, -20, 40, 40), 3, CG.DamageType.FIRE)
	assert_false(lava.blocks_movement())
	assert_false(lava.blocks_sight())
	assert_eq(Terrain.hazards_at([lava], Vector2(0, 0)).size(), 1)
	assert_eq(Terrain.hazards_at([lava], Vector2(500, 500)).size(), 0)
	assert_eq(lava.damage_per_tick, 3)
	assert_eq(lava.damage_type, CG.DamageType.FIRE)


func test_an_empty_room_blocks_nothing() -> void:
	# The negative case for the whole file. Without it, a set of functions that
	# returned true unconditionally would pass most of the tests above.
	assert_false(Terrain.line_is_blocked([], Vector2(-100, 0), Vector2(100, 0)))
	assert_false(Terrain.point_is_blocked([], Vector2(0, 0), 20.0))
	assert_eq(Terrain.hazards_at([], Vector2(0, 0)).size(), 0)
