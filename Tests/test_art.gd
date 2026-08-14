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


# ---------------------------------------------------------------------------
# AttackFX: per-damage-type attack visuals (PLAYTEST-NOTES 4, "every class
# needs an attack asset or animation"). Geometry-only, same reasoning as the
# silhouette tests above -- draw_* calls need a live canvas and are not
# where a shape or a number could be silently wrong.
# ---------------------------------------------------------------------------

const AttackFX := preload("res://Scripts/Art/AttackFX.gd")

const _ALL_DAMAGE_TYPES := [
	CG.DamageType.PHYSICAL, CG.DamageType.FIRE, CG.DamageType.WATER,
	CG.DamageType.AIR, CG.DamageType.EARTH, CG.DamageType.DIVINE,
	CG.DamageType.PROFANE, CG.DamageType.RAW,
]


func test_every_damage_type_has_a_projectile_shape() -> void:
	for dt in _ALL_DAMAGE_TYPES:
		var points := AttackFX.projectile_points(dt, 1.0, Vector2.RIGHT)
		assert_true(points.size() >= 3, "damage type %d has only %d points" % [dt, points.size()])


func test_projectile_shapes_are_distinct_per_damage_type() -> void:
	# Colour already carries most of the read at this size; shape is the
	# secondary cue and has to actually differ, or it is not one.
	var seen: Array = []
	for dt in _ALL_DAMAGE_TYPES:
		var points := AttackFX.projectile_points(dt, 1.0, Vector2.RIGHT)
		for other in seen:
			assert_ne(points, other, "damage type %d shares its shape with another type" % dt)
		seen.append(points)


func test_projectile_shapes_stay_inside_their_own_size() -> void:
	var size := 24.0
	for dt in _ALL_DAMAGE_TYPES:
		for p in AttackFX.projectile_points(dt, size, Vector2.RIGHT):
			assert_true(
				absf(p.x) <= size + 0.01 and absf(p.y) <= size + 0.01,
				"damage type %d has a point at %s, outside its own size of %f" % [dt, p, size]
			)


func test_projectile_shape_rotates_with_travel_direction() -> void:
	# A shot travelling straight up must not look like one travelling right --
	# the whole point of orienting by `forward` rather than always drawing the
	# authored (+X) pose.
	var right := AttackFX.projectile_points(CG.DamageType.PHYSICAL, 1.0, Vector2.RIGHT)
	var up := AttackFX.projectile_points(CG.DamageType.PHYSICAL, 1.0, Vector2.UP)
	assert_ne(right, up)
	# The forward tip (authored at local [1,0]) should now point up (-Y in
	# Godot's screen space), not sideways.
	assert_true(up[0].y < -0.9, "forward tip did not rotate to face up: %s" % up[0])


func test_projectile_shape_falls_back_for_an_unknown_damage_type() -> void:
	# _PROJECTILE_SHAPES is a Dictionary keyed by every CG.DamageType value
	# today; this asserts the .get() fallback actually fires rather than
	# crashing if a ninth type is ever added and forgotten here.
	var points := AttackFX.projectile_points(99, 1.0, Vector2.RIGHT)
	assert_true(points.size() >= 3)


# The three `wind_up_sweep_angle` tests that stood here were deleted with the
# ring itself in issue #85, deliberately not ported to the progress bar that
# replaced it: the bar is `Scripts/UI`'s and already carries its own test that
# it reads elapsed/total ratios rather than absolute ticks, which is the
# property those three were really protecting.


func test_impact_flash_grows_and_fades_with_progress() -> void:
	var base := 20.0
	assert_true(AttackFX.impact_flash_radius(base, 1.0) > AttackFX.impact_flash_radius(base, 0.0))
	assert_true(AttackFX.impact_flash_alpha(1.0) < AttackFX.impact_flash_alpha(0.0))
	assert_almost_eq(AttackFX.impact_flash_alpha(1.0), 0.0, 0.001)


func test_impact_flash_progress_is_clamped() -> void:
	# A caller that keeps a flash alive one frame past its own lifetime must
	# not get a negative alpha or a shrinking-past-zero radius.
	assert_almost_eq(AttackFX.impact_flash_alpha(1.5), AttackFX.impact_flash_alpha(1.0), 0.001)
	assert_almost_eq(AttackFX.impact_flash_radius(20.0, -0.5), AttackFX.impact_flash_radius(20.0, 0.0), 0.001)


# ---------------------------------------------------------------------------
# The UI art drop-in pipeline and its first two consumers: status badges
# (PLAYTEST-NOTES-2 item 2), ability icons (item 3), and the loader both sit on
# (item 15).
#
# What these check is what can go wrong *silently*: an icon that exists for
# every value today and stops existing when somebody adds one, a glyph that
# draws outside its own box, a drop-in path that quietly never finds the file.
# How they look is not testable and is not attempted -- Tools/UIArtPreview.tscn
# and the committed screenshots are for that.

const UIArt := preload("res://Scripts/Art/UIArt.gd")
const StatusIcons := preload("res://Scripts/Art/StatusIcons.gd")
const ActionIcons := preload("res://Scripts/Art/ActionIcons.gd")


func _every_status() -> Array:
	var out: Array = []
	for v in CG.Status.values():
		out.append(v)
	return out


## Every action any class or enemy in the real registry can actually order.
## Derived from the content rather than from a list typed here, because a list
## typed here would be a second artifact by the same author and would agree with
## itself while both were wrong.
func _every_reachable_action_id() -> Array:
	var out: Array = []
	for class_id in Registry.all_class_ids():
		for a in Registry.get_class_def(class_id).starting_actions:
			if not out.has(a):
				out.append(a)
	for enemy_id in Registry.all_enemy_ids():
		for a in Registry.get_enemy(enemy_id).actions:
			if not out.has(a):
				out.append(a)
	# A summoned unit's actions are ordered in a real fight but its id is not in
	# all_enemy_ids() by any path a class walks -- this is exactly the gap that
	# let a siege engine ship invisible.
	for action_id in out.duplicate():
		var action = Registry.get_action(action_id)
		if action == null or action.summons_unit_id == &"":
			continue
		var summoned = Registry.get_enemy(action.summons_unit_id)
		if summoned == null:
			continue
		for a in summoned.actions:
			if not out.has(a):
				out.append(a)
	return out


func test_every_status_has_a_badge_glyph() -> void:
	for s in _every_status():
		assert_true(
			StatusIcons.GLYPHS.has(s),
			"CG.Status.%s has no glyph in StatusIcons.GLYPHS" % CG.Status.keys()[s]
		)
		assert_true(
			(StatusIcons.GLYPHS[s] as Array).size() > 0,
			"CG.Status.%s has an empty glyph" % CG.Status.keys()[s]
		)


func _count_at(points: Array, y: float) -> int:
	var n := 0
	for p in points:
		if absf(p[1] - y) < 0.001:
			n += 1
	return n


func test_status_plate_direction_follows_is_harmful() -> void:
	# The stated rule, asserted rather than trusted: harmful points down,
	# beneficial points up, and CG.is_harmful() is the only source for it. A
	# second list in StatusIcons could drift; there is no second list, and this
	# fails if one is ever introduced.
	for s in _every_status():
		var pts := StatusIcons.plate_points(s)
		var lowest := -999.0
		var highest := 999.0
		for p in pts:
			lowest = maxf(lowest, p[1])
			highest = minf(highest, p[1])
		var label := String(CG.Status.keys()[s])
		if CG.is_harmful(s):
			assert_almost_eq(lowest, 1.0, 0.001, "%s should sit on a downward plate" % label)
			assert_eq(_count_at(pts, 1.0), 1, "%s plate should have exactly one bottom point" % label)
		else:
			assert_almost_eq(highest, -1.0, 0.001, "%s should sit on an upward plate" % label)
			assert_eq(_count_at(pts, -1.0), 1, "%s plate should have exactly one top point" % label)


func test_harmful_and_beneficial_rims_differ() -> void:
	assert_ne(StatusIcons.rim_color(CG.Status.BLEED), StatusIcons.rim_color(CG.Status.SHIELD))


func test_no_two_statuses_share_a_glyph() -> void:
	# The whole job of these badges is telling one status from another. Two
	# entries pointing at the same shape would pass every other check here.
	var seen: Array = []
	for s in _every_status():
		var g: Array = StatusIcons.GLYPHS[s]
		assert_false(seen.has(g), "CG.Status.%s reuses another status's glyph" % CG.Status.keys()[s])
		seen.append(g)


func test_every_reachable_action_has_an_icon() -> void:
	var reachable := _every_reachable_action_id()
	# The negative half: if this walk ever comes back empty the loop below
	# passes vacuously and says nothing, which is the failure mode a coverage
	# test has.
	assert_true(reachable.size() >= 20, "only found %d reachable actions, the registry walk is wrong" % reachable.size())
	for id in reachable:
		assert_true(ActionIcons.has_glyph(id), "action %s has no icon in ActionIcons.GLYPHS" % id)


func test_action_icon_table_has_no_entries_for_actions_that_do_not_exist() -> void:
	# The other direction: an icon left behind after content deletes an action
	# is dead weight and, worse, evidence that the two have drifted.
	for id in ActionIcons.GLYPHS.keys():
		assert_not_null(Registry.get_action(id), "ActionIcons has an icon for %s, which the registry does not define" % id)


func test_status_backed_action_icons_resolve_to_the_status_glyph() -> void:
	# Rule 2: an action whose whole effect is a status draws that status's
	# glyph. Stored as the enum value, so this checks the indirection actually
	# resolves rather than handing a bare int to the drawing loop.
	assert_eq(ActionIcons.glyph_for(&"warrior_guard"), StatusIcons.GLYPHS[CG.Status.BLOCK])
	assert_eq(ActionIcons.glyph_for(&"priest_haste"), StatusIcons.GLYPHS[CG.Status.HASTE])
	for id in ActionIcons.GLYPHS.keys():
		assert_true((ActionIcons.glyph_for(id) as Array).size() > 0, "action %s resolves to an empty glyph" % id)


func test_unknown_action_draws_a_placeholder_rather_than_nothing() -> void:
	# A blank looks like the feature failing; a placeholder looks like a missing
	# icon. Never reached today and asserted anyway.
	assert_false(ActionIcons.has_glyph(&"no_such_action"))
	assert_true((ActionIcons.glyph_for(&"no_such_action") as Array).size() > 0)


## The pairs of actions that are allowed to draw the same glyph, and why. Any
## other pair is a collision and fails the test below.
const _DELIBERATE_SHARED_GLYPHS := {
	# `archer_shot` is retired from the bestiary -- `core_actions.gd` says so in
	# its own description, and no enemy or class lists it. It survives only so an
	# older fixture resolves, so it can never be drawn beside `goblin_arrow`, or
	# at all.
	"archer_shot|goblin_arrow": true,
	# Spout and Blast are the same jet of water from the same unit, one free and
	# one not. Same verb, same element, and telling them apart buys the player
	# nothing they cannot get from the bar's length. Left shared on purpose.
	"geyser_blast|geyser_spout": true,
}


func test_no_two_ability_icons_share_a_glyph_by_accident() -> void:
	# The test the icon sheet was doing by eye. `siege_master_shot` and
	# `siege_engine_bolt` both drew `_BOLT_HEAVY`, and a Siege Master builds the
	# engine and then fights beside it -- so the same icon sat over two units at
	# once, on two bars, which is the exact case rule 4 exists to prevent. It
	# survived a correct-looking table and two rendered sheets. An accidental
	# share is now a red test rather than something somebody has to spot.
	var seen: Dictionary = {}
	for id in ActionIcons.GLYPHS.keys():
		var glyph: Array = ActionIcons.glyph_for(id)
		for other in seen.keys():
			if seen[other] != glyph:
				continue
			var pair := "%s|%s" % ([String(id), String(other)] if String(id) < String(other) else [String(other), String(id)])
			assert_true(
				_DELIBERATE_SHARED_GLYPHS.has(pair),
				"%s and %s draw the same glyph. If that is deliberate, add '%s' to _DELIBERATE_SHARED_GLYPHS with the reason; otherwise give one of them its own shape." % [id, other, pair]
			)
		seen[id] = glyph
	# The negative half: if the allowlist ever names a pair that no longer shares
	# a glyph, the entry is stale and its reasoning is describing nothing.
	for pair in _DELIBERATE_SHARED_GLYPHS.keys():
		var ids: PackedStringArray = String(pair).split("|")
		assert_eq(
			ActionIcons.glyph_for(StringName(ids[0])), ActionIcons.glyph_for(StringName(ids[1])),
			"_DELIBERATE_SHARED_GLYPHS still excuses '%s', but those two no longer share a glyph" % pair
		)


func test_glyph_geometry_stays_inside_its_own_rect() -> void:
	# A glyph escaping its box shows up as an icon bleeding into the unit next
	# to it, which reads as a rendering bug rather than as bad art.
	var rect := Rect2(100.0, 40.0, 16.0, 16.0)
	var all: Array = []
	for s in _every_status():
		all.append(StatusIcons.GLYPHS[s])
	for id in ActionIcons.GLYPHS.keys():
		all.append(ActionIcons.glyph_for(id))
	all.append([{"poly": StatusIcons.PLATE_GOOD}, {"poly": StatusIcons.PLATE_BAD}, {"poly": ActionIcons.PLATE}])
	for glyph in all:
		for part in glyph:
			for p in UIArt.glyph_points(part, rect):
				assert_true(
					rect.grow(0.01).has_point(p),
					"glyph point %s escapes its rect %s" % [p, rect]
				)


func test_glyph_points_are_centred_and_scaled_by_the_rect() -> void:
	var rect := Rect2(0.0, 0.0, 20.0, 20.0)
	var pts := UIArt.glyph_points({"poly": [[0.0, 0.0], [1.0, 0.0], [0.0, -1.0]]}, rect)
	assert_eq(pts[0], Vector2(10.0, 10.0))
	assert_eq(pts[1], Vector2(20.0, 10.0))
	assert_eq(pts[2], Vector2(10.0, 0.0))


func test_glyph_rotation_turns_a_part_about_the_rect_centre() -> void:
	# `rot` is what stops warrior_strike rendering as a plus sign, so it is
	# load-bearing rather than decorative.
	var rect := Rect2(0.0, 0.0, 20.0, 20.0)
	var upright := UIArt.glyph_points({"poly": [[0.0, -1.0]]}, rect)
	var quarter := UIArt.glyph_points({"poly": [[0.0, -1.0]], "rot": PI * 0.5}, rect)
	assert_eq(upright[0], Vector2(10.0, 0.0))
	assert_almost_eq(quarter[0].x, 20.0, 0.001)
	assert_almost_eq(quarter[0].y, 10.0, 0.001)


func test_glyph_rotation_moves_dot_and_arc_centres_too() -> void:
	# A rotated glyph whose polygons turned and whose dots stayed put would come
	# apart, and it would only be visible by looking.
	var rect := Rect2(0.0, 0.0, 20.0, 20.0)
	var still := UIArt.glyph_center({}, [0.0, -1.0, 0.2], rect)
	var turned := UIArt.glyph_center({"rot": PI * 0.5}, [0.0, -1.0, 0.2], rect)
	assert_eq(still, Vector2(10.0, 0.0))
	assert_almost_eq(turned.x, 20.0, 0.001)


func test_glyph_scales_to_the_shorter_side_of_a_non_square_rect() -> void:
	# A caller handing this a wide rect should get a round icon in the middle,
	# not an ellipse. Aspect distortion reads as a bug.
	var pts := UIArt.glyph_points({"poly": [[1.0, 1.0]]}, Rect2(0.0, 0.0, 40.0, 10.0))
	assert_eq(pts[0], Vector2(25.0, 10.0))


func test_ui_art_returns_null_for_a_name_with_no_file() -> void:
	# The normal case today, and it must be silent: a missing override is not
	# an error and every drawing function relies on that.
	UIArt.clear_cache()
	assert_eq(UIArt.texture_for(&"definitely_not_a_real_ui_asset"), null)
	assert_false(UIArt.has_art(&"status/definitely_not_a_real_status"))


func test_a_dropped_in_png_is_found_with_no_registration() -> void:
	# The item-15 claim, exercised end to end rather than reasoned about: write
	# a PNG into Assets/UI under a name the game asks for, and the loader finds
	# it with no import, no registration and no code change. Removed again so
	# the generated defaults are what ships.
	var art_name := StatusIcons.art_name(CG.Status.BLEED)
	assert_eq(String(art_name), "status/bleed")
	var path := "res://Assets/UI/%s.png" % art_name
	assert_false(FileAccess.file_exists(path), "%s already exists; this test would not prove anything" % path)

	DirAccess.make_dir_recursive_absolute("res://Assets/UI/status")
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.0, 1.0, 1.0))
	assert_eq(image.save_png(path), OK, "could not write the test override to %s" % path)

	UIArt.clear_cache()
	var tex := UIArt.texture_for(art_name)
	assert_not_null(tex, "a PNG dropped into Assets/UI was not picked up")
	assert_eq(tex.get_width(), 8)

	DirAccess.remove_absolute(path)
	UIArt.clear_cache()
	assert_eq(UIArt.texture_for(art_name), null, "the override survived its own deletion")


func test_status_row_layout_is_evenly_spaced_and_measurable() -> void:
	var rects := StatusIcons.layout_row(Vector2(10.0, 5.0), 3, 14.0, 4.0)
	assert_eq(rects.size(), 3)
	assert_eq(rects[0].position, Vector2(10.0, 5.0))
	assert_eq(rects[1].position, Vector2(28.0, 5.0))
	assert_eq(rects[2].position, Vector2(46.0, 5.0))
	# row_width must agree with where the last badge actually ends, or a caller
	# centring a row over a unit centres it wrongly.
	assert_almost_eq(StatusIcons.row_width(3, 14.0, 4.0), rects[2].end.x - rects[0].position.x, 0.001)
	assert_almost_eq(StatusIcons.row_width(0, 14.0, 4.0), 0.0, 0.001)


func test_status_art_names_are_unique_and_lower_case() -> void:
	var seen: Array = []
	for s in _every_status():
		var n := StatusIcons.art_name(s)
		assert_eq(String(n), String(n).to_lower())
		assert_false(seen.has(n), "two statuses share the drop-in name %s" % n)
		seen.append(n)


func test_action_art_name_is_the_action_id() -> void:
	assert_eq(ActionIcons.art_name(&"warrior_execute"), &"action/warrior_execute")
