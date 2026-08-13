extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Silhouettes := preload("res://Scripts/Art/Silhouettes.gd")

## MANAGER-OWNED, alongside Scripts/Art/.
##
## These check the parts of the placeholder art that can go wrong silently. How
## it *looks* is not testable and is not attempted: that is what
## Tools/ArtPreview.tscn and the committed screenshot are for.

const Registry := preload("res://Scripts/Content/Registry.gd")

const CLASS_SHAPES := [&"warrior", &"priest", &"geysermancer", &"siege_master", &"abomination"]

## Shapes drawn for enemies that do not exist yet. Kept deliberately; they cost
## nothing and later floors will want them.
const UNUSED_SHAPES := [&"rat", &"grub", &"brute"]


func test_every_registered_class_and_enemy_has_a_shape() -> void:
	# The check that was missing, and the reason it was missing is instructive:
	# I wrote silhouettes named rat, grub and brute before any content existed,
	# teal named their enemies dungeon_grunt, dungeon_archer and dungeon_cultist,
	# and every enemy in the game drew the unknown-shape fallback for hours.
	# Both halves were individually correct. Nothing compared them, because they
	# are owned by different sessions and neither one is wrong on its own.
	#
	# Asks the Registry rather than a list typed in this file. A list here would
	# be a second artifact by the same author as the first, and it would agree
	# with itself forever.
	# Enemies are reached through the encounters rather than through a registry
	# listing. That was the better question right up until it was not.
	#
	# **It missed the siege engine, and the player found it by playing:** "siege
	# master engines are currently invisible". A summoned unit spawns in no
	# encounter, so walking encounter spawn lists could never see it, and it drew
	# the unknown-shape fallback in every real fight.
	#
	# The comment that used to sit here said "an enemy that never spawns does not
	# need art yet, and one that spawns always does". True when written, false the
	# moment mid-fight summoning landed. **A test's assumption can rot without the
	# test ever failing**, which is the same failure as an instrument that stops
	# measuring what it claims -- and this project has now been bitten by that
	# more times than by any bug.
	#
	# So both sources are checked: what encounters spawn, and what actions summon.
	for id in Registry.all_class_ids():
		assert_true(Silhouettes.has_shape(id), "class '%s' is registered but has no silhouette" % id)

	var checked := 0
	for encounter_id in Registry.all_encounter_ids():
		var encounter := Registry.get_encounter(encounter_id)
		for spawn in encounter.enemy_spawns:
			var enemy_id: StringName = spawn.get("enemy_id", &"")
			assert_true(
				Silhouettes.has_shape(enemy_id),
				"enemy '%s' spawns in encounter '%s' but has no silhouette" % [enemy_id, encounter_id]
			)
			checked += 1

	# Summoned units, which no encounter lists. ActionDef.summons_unit_id is the
	# only place they are named, and it is reached through the actions a class
	# or an enemy actually has -- Registry has all_class_ids/all_enemy_ids but no
	# all_action_ids, checked rather than assumed.
	var action_ids: Array[StringName] = []
	for class_id in Registry.all_class_ids():
		var cls := Registry.get_class_def(class_id)
		if cls != null:
			for aid in cls.starting_actions:
				if not action_ids.has(aid):
					action_ids.append(aid)
	for enemy_id in Registry.all_enemy_ids():
		var enemy := Registry.get_enemy(enemy_id)
		if enemy != null:
			for aid in enemy.actions:
				if not action_ids.has(aid):
					action_ids.append(aid)

	for action_id in action_ids:
		var action := Registry.get_action(action_id)
		if action == null or action.summons_unit_id == &"":
			continue
		assert_true(
			Silhouettes.has_shape(action.summons_unit_id),
			"action '%s' summons '%s' but it has no silhouette" % [action_id, action.summons_unit_id]
		)
		checked += 1
	assert_true(checked > 0, "no enemy spawns were checked; this test would pass on an empty game")


func test_every_class_in_the_readme_has_a_shape() -> void:
	# A missing shape does not crash. It falls back to the unknown-marker
	# diamond, which on a busy screen looks like a deliberate enemy type rather
	# than a mistake, so nothing would report it.
	for id in CLASS_SHAPES:
		assert_true(Silhouettes.has_shape(id), "no silhouette for class '%s'" % id)


func test_the_unused_shapes_are_still_there() -> void:
	for id in UNUSED_SHAPES:
		assert_true(Silhouettes.has_shape(id), "no silhouette for '%s'" % id)


func test_an_unknown_shape_is_reported_as_unknown() -> void:
	# The negative case. Without it, a has_shape that returned true for
	# everything would pass both tests above perfectly.
	assert_false(Silhouettes.has_shape(&"not_a_real_shape"))
	assert_false(Silhouettes.has_shape(&""))


func test_shape_ids_are_sorted_and_complete() -> void:
	var ids := Silhouettes.shape_ids()
	assert_true(ids.size() >= CLASS_SHAPES.size() + UNUSED_SHAPES.size())
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


# ---------------------------------------------------------------------------
# The art is meant to be replaced. These check that the replacing works and
# that the instructions for it stay true.
# ---------------------------------------------------------------------------

const UnitArt := preload("res://Scripts/Art/UnitArt.gd")


func test_with_no_art_files_every_shape_falls_back_to_polygons() -> void:
	# The state the project ships in. If this ever fails it means something is
	# being picked up from Assets/Units that should not be, which would be
	# confusing in exactly the way a caching bug is.
	for id in Silhouettes.shape_ids():
		for team in [CG.Team.PLAYER, CG.Team.ENEMY]:
			if UnitArt.has_art(id, team):
				continue
			var parts := Silhouettes.build_parts(id, 24.0, team, CG.DamageType.FIRE)
			assert_true(parts.size() >= 3, "%s lost its placeholder" % id)


func test_a_missing_art_file_is_not_an_error() -> void:
	# Dropping in art is opt-in per unit, so the absence of a file has to be
	# silent. If this ever pushed an error, the console would be unreadable and
	# people would learn to ignore it.
	assert_eq(UnitArt.texture_for(&"definitely_not_a_unit", CG.Team.PLAYER), null)
	assert_false(UnitArt.has_art(&"definitely_not_a_unit", CG.Team.ENEMY))


func test_the_replacement_instructions_match_the_real_content() -> void:
	# Assets/Units/README.md tells whoever replaces the art which filenames to
	# use. If somebody adds an enemy and does not update it, that person finds
	# out here rather than the artist finding out by dropping in a PNG that
	# never appears.
	var readme := FileAccess.get_file_as_string("res://Assets/Units/README.md")
	assert_ne(readme, "", "Assets/Units/README.md is missing")

	for class_id in Registry.all_class_ids():
		assert_true(
			readme.contains("%s.png" % class_id),
			"class '%s' is registered but Assets/Units/README.md does not list %s.png" % [class_id, class_id]
		)

	var checked := 0
	for encounter_id in Registry.all_encounter_ids():
		for spawn in Registry.get_encounter(encounter_id).enemy_spawns:
			var enemy_id: StringName = spawn.get("enemy_id", &"")
			assert_true(
				readme.contains("%s.png" % enemy_id),
				"enemy '%s' spawns but Assets/Units/README.md does not list %s.png" % [enemy_id, enemy_id]
			)
			checked += 1
	assert_true(checked > 0, "no enemy spawns checked; this test would pass on an empty game")
