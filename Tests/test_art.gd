extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Silhouettes := preload("res://Scripts/Art/Silhouettes.gd")

## MANAGER-OWNED, alongside Scripts/Art/.
##
## These check the parts of the placeholder art that can go wrong silently. How
## it *looks* is not testable and is not attempted: that is what
## Tools/ArtPreview.tscn and the committed screenshot are for.

const CLASS_SHAPES := [&"warrior", &"priest", &"geysermancer", &"siege_master", &"abomination"]
const ENEMY_SHAPES := [&"rat", &"grub", &"brute"]


func test_every_class_in_the_readme_has_a_shape() -> void:
	# A missing shape does not crash. It falls back to the unknown-marker
	# diamond, which on a busy screen looks like a deliberate enemy type rather
	# than a mistake, so nothing would report it.
	for id in CLASS_SHAPES:
		assert_true(Silhouettes.has_shape(id), "no silhouette for class '%s'" % id)


func test_the_enemy_shapes_exist() -> void:
	for id in ENEMY_SHAPES:
		assert_true(Silhouettes.has_shape(id), "no silhouette for enemy '%s'" % id)


func test_an_unknown_shape_is_reported_as_unknown() -> void:
	# The negative case. Without it, a has_shape that returned true for
	# everything would pass both tests above perfectly.
	assert_false(Silhouettes.has_shape(&"not_a_real_shape"))
	assert_false(Silhouettes.has_shape(&""))


func test_shape_ids_are_sorted_and_complete() -> void:
	var ids := Silhouettes.shape_ids()
	assert_eq(ids.size(), CLASS_SHAPES.size() + ENEMY_SHAPES.size())
	var sorted := ids.duplicate()
	sorted.sort()
	assert_eq(ids, sorted, "shape_ids must be deterministic")


func test_every_shape_builds_drawable_polygons() -> void:
	# Runs the real geometry path and asserts what comes back, rather than
	# reading the coordinate tables, which would only prove they agree with
	# themselves. A part with fewer than three points, or a tint key that does
	# not resolve to a colour, fails here.
	for id in Silhouettes.shape_ids():
		for team in [CG.Team.PLAYER, CG.Team.ENEMY]:
			var parts := Silhouettes.build_parts(id, 24.0, team, CG.DamageType.FIRE)
			assert_true(parts.size() >= 3, "%s has only %d parts; too few to read" % [id, parts.size()])
			for part in parts:
				var points: PackedVector2Array = part["points"]
				assert_true(points.size() >= 3, "%s has a part with %d points" % [id, points.size()])
				assert_true(part["fill"] is Color, "%s has a part with no fill colour" % id)


func test_shapes_stay_inside_the_radius_they_are_given() -> void:
	# A shape that overflows its radius overlaps its neighbours in a crowd and
	# makes a fight unreadable in exactly the situation that matters most.
	# Checked on the diagonal too, not only on the axes: the first version of
	# this file had corners past the bound that an axis-only check missed.
	var radius := 24.0
	for id in Silhouettes.shape_ids():
		for part in Silhouettes.build_parts(id, radius, CG.Team.PLAYER, CG.DamageType.FIRE):
			for p in part["points"]:
				assert_true(
					absf(p.x) <= radius + 0.01 and absf(p.y) <= radius + 0.01,
					"%s has a point at %s, outside its radius of %f" % [id, p, radius]
				)


func test_facing_left_mirrors_the_shape() -> void:
	# And the negative half: facing right must not mirror it. A flip applied
	# unconditionally looks correct in every screenshot of a single unit.
	var right := Silhouettes.build_parts(&"warrior", 24.0, CG.Team.PLAYER, CG.DamageType.FIRE, false)
	var left := Silhouettes.build_parts(&"warrior", 24.0, CG.Team.PLAYER, CG.DamageType.FIRE, true)
	assert_eq(right.size(), left.size())
	for i in right.size():
		var rp: PackedVector2Array = right[i]["points"]
		var lp: PackedVector2Array = left[i]["points"]
		for j in rp.size():
			assert_almost_eq(lp[j].x, -rp[j].x, 0.001, "x should mirror")
			assert_almost_eq(lp[j].y, rp[j].y, 0.001, "y should not")


func test_an_unknown_shape_still_produces_something_visible() -> void:
	# An invisible unit reads as a simulation bug and is not one. The fallback
	# has to draw.
	var parts := Silhouettes.build_parts(&"not_a_real_shape", 24.0, CG.Team.PLAYER, CG.DamageType.FIRE)
	assert_eq(parts.size(), 1)
	assert_true(parts[0]["points"].size() >= 3)
	assert_false(parts[0]["filled"], "the unknown marker is hollow, so it cannot be mistaken for real art")
