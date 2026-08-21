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


func test_the_arena_draws_it_and_the_unit_does_not() -> void:
	# Issue 332. UnitViews are siblings, so a plate drawn inside one of them
	# paints over whichever units come earlier in the child order -- the ones it
	# exists to shelter. Drawn from the arena, which is their parent, it cannot.
	var arena := FileAccess.get_file_as_string("res://Scripts/UI/ArenaFloor.gd")
	assert_true(arena.contains("ShieldWall.draw_all("),
		"ArenaFloor._draw no longer draws the shield, so nobody does")
	var unit := FileAccess.get_file_as_string("res://Scripts/UI/UnitView.gd")
	assert_false(unit.contains("ShieldWall."),
		"UnitView draws the plate again, which puts it back on top of the crowd")


func test_the_haft_reaches_the_body_that_is_holding_it() -> void:
	# The plate's own back edge sits a standoff clear of the body, and bodies
	# draw at DISPLAY_SCALE while the plate is world-true, so the two cannot
	# meet by construction. The haft spans the gap instead.
	for raw in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2(3.0, -4.0).normalized()]:
		var facing: Vector2 = raw
		var e := _extent(ShieldWall.haft_points(facing, STANDOFF), facing)
		assert_almost_eq(e["along_lo"], 0.0, 0.01,
			"facing %s draws a haft that starts clear of the shielder's own centre" % facing)
		assert_true(e["along_hi"] > STANDOFF,
			"facing %s draws a haft that stops short of the plate" % facing)


func test_the_frontage_is_divided_into_panels() -> void:
	# One long unbroken band is what a blind playtester called a teal sliver and
	# could not identify. The seams are what make it a row of shields.
	var seams := ShieldWall.seam_points(Vector2.RIGHT, ShieldWall.half_width(), STANDOFF)
	assert_eq(seams.size(), ShieldWall.PANELS - 1,
		"a plate of %d panels needs %d joins" % [ShieldWall.PANELS, ShieldWall.PANELS - 1])
	# Counting the seams against PANELS alone proves nothing -- PANELS of 1 draws
	# no seam and satisfies it. A panel is a pawn's worth of cover, which is what
	# the player asked the frontage to be: "5 times as long so that other units
	# can use it as cover".
	var panel := CombatSim.SHIELD_WIDTH / float(ShieldWall.PANELS)
	var pawn := CombatUnit.new().radius * 2.0
	assert_true(panel >= pawn * 0.6 and panel <= pawn * 1.6,
		"a panel is %.1f world units against a pawn's %.1f: it is not a pawn's worth of cover" % [panel, pawn])
	var seen := {}
	for line in seams:
		var seam: PackedVector2Array = line
		assert_almost_eq(seam[0].x, STANDOFF, 0.01, "a seam must start at the plate's back edge")
		assert_true(seam[1].x > seam[0].x, "a seam must cross the plate, not sit on its edge")
		assert_almost_eq(seam[0].y, seam[1].y, 0.01, "a seam must run straight across the plate")
		assert_true(absf(seam[0].y) < ShieldWall.half_width(), "a seam must fall inside the frontage")
		seen[snappedf(seam[0].y, 0.01)] = true
	assert_eq(seen.size(), seams.size(), "two joins are drawn in the same place")


func test_the_plate_is_trimmed_to_the_room_it_is_standing_in() -> void:
	# The plate ran out through the arena wall and off the screen, which was
	# half of what read as a rendering artifact rather than as cover.
	# Stood against the bottom wall facing across it, so the plate's own frontage
	# runs half of its length out of the room.
	var position := Vector2(0.0, CG.ARENA_HALF_HEIGHT - 10.0)
	var wall := ShieldWall.wall_points(Vector2.RIGHT, ShieldWall.half_width(), STANDOFF)
	var pieces := Geometry2D.intersect_polygons(wall, ShieldWall.room_for(position))
	assert_false(pieces.is_empty(), "the trim left nothing at all of a plate that is half inside the room")
	for piece in pieces:
		for p in piece:
			var world: Vector2 = p + position
			assert_true(absf(world.x) <= CG.ARENA_HALF_WIDTH + 0.01
					and absf(world.y) <= CG.ARENA_HALF_HEIGHT + 0.01,
				"the trimmed plate still puts ink at %s, outside the arena" % world)


func test_the_trim_leaves_the_plate_alone_in_open_ground() -> void:
	# The negative half: a clip that ate the plate everywhere would pass the
	# test above.
	var wall := ShieldWall.wall_points(Vector2.RIGHT, ShieldWall.half_width(), STANDOFF)
	var pieces := Geometry2D.intersect_polygons(wall, ShieldWall.room_for(Vector2.ZERO))
	assert_eq(pieces.size(), 1, "a shielder in the middle of the room must keep one whole plate")
	var e := _extent(pieces[0], Vector2.RIGHT)
	assert_almost_eq(e["across_hi"] - e["across_lo"], CombatSim.SHIELD_WIDTH, 0.01,
		"the trim narrowed a plate that was nowhere near a wall")


func test_a_badge_sits_inside_every_panel_of_the_plate() -> void:
	# Three strangers in a row read the plate as terrain, a blade or an
	# artifact, so each panel now carries the SHIELDING badge; a badge whose
	# centre is off the plate is a badge floating beside it.
	var half := ShieldWall.half_width()
	var wall := ShieldWall.wall_points(Vector2.RIGHT, half, STANDOFF)
	var centers := ShieldWall.panel_centers(Vector2.RIGHT, half, STANDOFF)
	assert_eq(centers.size(), ShieldWall.PANELS, "one badge per panel")
	for c in centers:
		assert_true(Geometry2D.is_point_in_polygon(c, wall),
			"a panel badge is centred at %s, which is not on the plate" % c)


func test_the_panel_badges_are_spread_across_the_whole_frontage() -> void:
	# The negative half: five badges stacked at the middle would pass the test
	# above and say nothing about the plate's length.
	var half := ShieldWall.half_width()
	var centers := ShieldWall.panel_centers(Vector2.RIGHT, half, STANDOFF)
	var e := _extent(centers, Vector2.RIGHT)
	var step := CombatSim.SHIELD_WIDTH / float(ShieldWall.PANELS)
	assert_almost_eq(e["across_hi"] - e["across_lo"], CombatSim.SHIELD_WIDTH - step, 0.01,
		"the badges do not span the frontage they are meant to name")


func test_the_name_never_lies_over_the_plate_it_names() -> void:
	# Centring the chip on a point in front of the lip is not enough: the chip
	# is upright while the plate turns, so at an eastward facing half of it lay
	# back over the badges.
	for facing in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2(0.983, 0.182).normalized()]:
		var half := ShieldWall.half_width()
		var wall := ShieldWall.wall_points(facing, half, STANDOFF)
		var chip := ShieldWall.label_chip(facing, STANDOFF)
		var lip: float = _extent(wall, facing)["along_hi"]
		var corners := PackedVector2Array([chip.position, chip.position + Vector2(chip.size.x, 0.0),
			chip.position + Vector2(0.0, chip.size.y), chip.end])
		for c in corners:
			assert_true(c.dot(facing.normalized()) >= lip - 0.01,
				"the name chip reaches back over the plate at facing %s" % facing)
			assert_false(Geometry2D.is_point_in_polygon(c, wall),
				"a corner of the name chip is on the plate at facing %s" % facing)
		assert_almost_eq(_extent(corners, facing)["along_lo"], lip + ShieldWall.LABEL_STANDOFF, 0.01,
			"the name is not standing off the lip at facing %s" % facing)
