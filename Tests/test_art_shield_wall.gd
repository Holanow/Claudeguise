extends "res://Tests/TestCase.gd"


## The drawn shield has to say three things: how wide it is, which way it
## faces, and that it is up right now. The width is the one that can lie
## silently, so it is read from the simulation's own constant.

const STANDOFF := 33.0


func _unit(facing: Vector2, shielding: bool) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 1
	u.team = CG.Team.PLAYER
	u.hp = 10
	u.hp_max = 10
	u.facing = facing
	if shielding:
		u.statuses[CG.Status.SHIELDING] = 999
	return u


## The extent of the plate across `facing` and along it, in world units.
func _extent(points: PackedVector2Array, facing: Vector2) -> Dictionary:
	var f := facing.normalized()
	var perp := Vector2(-f.y, f.x)
	var out := {"across_lo": INF, "across_hi": -INF, "along_lo": INF, "along_hi": -INF}
	for p in points:
		out["across_lo"] = minf(out["across_lo"], p.dot(perp))
		out["across_hi"] = maxf(out["across_hi"], p.dot(perp))
		out["along_lo"] = minf(out["along_lo"], p.dot(f))
		out["along_hi"] = maxf(out["along_hi"], p.dot(f))
	return out


func test_the_drawn_frontage_is_the_simulations_own_band() -> void:
	# A hand-written width drifts from `SHIELD_WIDTH` the first time anybody
	# tunes it, and then the picture teaches the player something false about
	# where it is safe to stand.
	assert_almost_eq(ShieldWall.half_width() * 2.0, CombatSim.SHIELD_WIDTH, 0.0001,
		"the plate's frontage must be CombatSim.SHIELD_WIDTH, the band _find_shielder blocks")
	for raw in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2(3.0, -4.0).normalized()]:
		var facing: Vector2 = raw
		var e := _extent(ShieldWall.wall_points(facing, ShieldWall.half_width(), STANDOFF), facing)
		assert_almost_eq(e["across_hi"] - e["across_lo"], CombatSim.SHIELD_WIDTH, 0.01,
			"facing %s draws a frontage that is not the band the simulation blocks" % facing)


func test_the_frontage_follows_the_width_it_is_given() -> void:
	# The negative half of the test above: if the span were a constant, that
	# one would pass with the number hardcoded.
	var e := _extent(ShieldWall.wall_points(Vector2.RIGHT, 17.0, STANDOFF), Vector2.RIGHT)
	assert_almost_eq(e["across_hi"] - e["across_lo"], 34.0, 0.01,
		"the drawn span ignores its own half-width argument")


func test_the_plate_is_wholly_in_front_and_reaches_furthest_at_its_middle() -> void:
	# A shield that stops shots from one side only is a lie if it looks
	# symmetric about the body.
	for raw in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2(-2.0, 1.0).normalized()]:
		var facing: Vector2 = raw
		var points := ShieldWall.wall_points(facing, ShieldWall.half_width(), STANDOFF)
		var e := _extent(points, facing)
		assert_true(e["along_lo"] >= STANDOFF - 0.01,
			"facing %s draws part of the plate behind the shielder" % facing)
		var f := facing.normalized()
		var perp := Vector2(-f.y, f.x)
		var nose := points[0]
		for p in points:
			if p.dot(f) > nose.dot(f):
				nose = p
		assert_almost_eq(nose.dot(perp), 0.0, 0.01,
			"facing %s does not bow forward at its middle, so it has no front" % facing)


func test_it_is_drawn_only_while_the_status_is_up() -> void:
	assert_true(ShieldWall.is_up(_unit(Vector2.RIGHT, true)),
		"a facing shielder must draw its plate")
	assert_false(ShieldWall.is_up(_unit(Vector2.RIGHT, false)),
		"the plate must go when SHIELDING goes")


func test_a_shielder_with_no_facing_draws_nothing_because_it_blocks_nothing() -> void:
	# `CombatSim._find_shielder` skips a candidate whose facing is ZERO. The
	# drawing agrees with it rather than inventing a direction.
	assert_false(ShieldWall.is_up(_unit(Vector2.ZERO, true)),
		"a shielder with no facing blocks nothing and must draw nothing")


func test_a_dead_shielder_draws_nothing() -> void:
	var u := _unit(Vector2.RIGHT, true)
	u.hp = 0
	u.alive = false
	assert_false(ShieldWall.is_up(u), "a corpse must not hold cover")


func test_the_unit_view_actually_calls_it() -> void:
	# Geometry nothing calls is geometry nobody sees, which is the defect this
	# issue is about in the first place.
	var text := FileAccess.get_file_as_string("res://Scripts/UI/UnitView.gd")
	assert_true(text.contains("ShieldWall.draw_for("),
		"UnitView._draw no longer draws the shield")
