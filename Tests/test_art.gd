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

## Shapes that exist ahead of the content that will spawn them, named here
## because **no other test in this file can see them.**
##
## `test_every_registered_class_and_enemy_has_a_shape` walks encounter spawn
## lists, and a unit nothing spawns appears in none. That is exactly how the
## Siege Master's engine shipped invisible for weeks -- it was drawing the
## unknown-shape fallback in real fights and the art suite was green throughout,
## because a summoned unit is in no spawn list either.
##
## So anything drawn before its content exists goes here and gets checked like
## content. The Rat King is floor 1's miniboss and the rat is what its attacks
## leave behind; neither is in an encounter yet.
const AHEAD_OF_CONTENT_SHAPES := [&"rat_king", &"rat", &"siege_engine", &"stalker"]


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


func test_shapes_drawn_ahead_of_their_content_are_real_shapes() -> void:
	# Not just `has_shape`: the failure being guarded against is a unit drawing
	# the unknown-shape fallback in a real fight, and `has_shape` is exactly the
	# thing that would have been false while nobody looked. So this asserts the
	# shape is present AND that what it builds is not the fallback.
	var unknown := Silhouettes.build_parts(&"not_a_real_shape", 40.0, CG.Team.ENEMY, CG.DamageType.PHYSICAL)
	for id in AHEAD_OF_CONTENT_SHAPES:
		assert_true(Silhouettes.has_shape(id), "no silhouette for '%s'" % id)
		var parts := Silhouettes.build_parts(id, 40.0, CG.Team.ENEMY, CG.DamageType.PHYSICAL)
		assert_true(parts.size() > unknown.size(),
			"'%s' builds %d polygons, the unknown fallback builds %d -- it is drawing the fallback" % [
				id, parts.size(), unknown.size()])


func test_the_rat_king_reads_as_more_than_one_animal() -> void:
	# THE DESIGN RULE, ASSERTED AS GEOMETRY, and it is a stand-in so it says what
	# it stands for: every other unit in this game reads as ONE creature and the
	# Rat King has to read as MANY -- "a big collection of rats joined at the
	# tail". The cue that survives being shrunk to 50 pixels is a SCALLOPED top
	# edge: several rounded backs with real sky between them. One dome is one
	# animal at any size.
	#
	# So: sample the top of the silhouette across its width and count the peaks.
	# Two passes of this shape failed for opposite reasons -- humps overlapped
	# into a single dome, then humps sharpened into a mountain range -- and this
	# catches the first. It cannot catch the second; only looking can, which is
	# why Tools/RatKingSheet.tscn exists and why the sheet is committed.
	# **What this measures, stated exactly, because it is not quite what the
	# design claim says.** It counts peaks in the whole outline, and the tail
	# strands are part of that outline, so a Rat King with flattened backs but
	# intact strands would still pass. It is a guard against the shape collapsing
	# into a dome, not proof that the humps specifically are doing the work.
	# Measured: rat_king 8, the_warden 1, ghoul 1, brute 1, grub 0.
	var peaks := _peaks(&"rat_king")
	assert_true(peaks >= 2,
		"the Rat King's outline has %d peaks; it reads as one animal, not a pile" % peaks)

	# The negative half, and it is what makes the number above mean anything: a
	# single-creature silhouette must NOT pass this. Without it, a sampling bug
	# that found peaks everywhere would look exactly like success.
	for one_animal in [&"the_warden", &"ghoul", &"brute"]:
		assert_true(_peaks(one_animal) < peaks,
			"'%s' scores %d peaks against the Rat King's %d -- this is not measuring 'many'" % [
				one_animal, _peaks(one_animal), peaks])


func test_the_rat_king_outline_keeps_headroom_over_a_single_creature() -> void:
	# The margin, guarded separately, per this project's own rule: a floor of
	# `>= 2` reads identically at 8 and at 2 and speaks only on the build that
	# breaks it, which lands on whoever touched the file next rather than
	# whoever caused the drift. Measured at 8 against a single-creature baseline
	# of 1. This fires while the shape is still passing.
	assert_true(_peaks(&"rat_king") >= 4,
		"the Rat King is down to %d peaks from a measured 8; the pile is flattening out" % _peaks(&"rat_king"))


func test_the_rat_is_flatter_than_the_shapes_it_could_be_confused_with() -> void:
	# The rat's identity, checked rather than asserted in a comment. The first
	# version WAS a third mound, indistinguishable from `grub` and `brute` at a
	# glance -- the failure the top of Silhouettes.gd warns about, sitting in the
	# file underneath the warning.
	#
	# Deliberately NOT "flattest of every shape in the game". It is, at 1.21
	# against grub's 1.15, and asserting a superlative on a six-percent margin
	# would hand a failure to whoever next edits an unrelated shape. The design
	# requirement is that it is not mistakable for the mounds, and that is what
	# is checked.
	var ratio := _aspect(&"rat")
	for id in [&"grub", &"brute", &"ghoul", &"goblin", &"rat_king"]:
		assert_true(ratio > _aspect(id),
			"'%s' is %.2f wide-to-tall and the rat is only %.2f; the rat must read as the long low one" % [
				id, _aspect(id), ratio])


func _peaks(id: StringName) -> int:
	var radius := 200.0
	var bins := 40
	var top := []
	top.resize(bins)
	top.fill(INF)
	for part in Silhouettes.build_parts(id, radius, CG.Team.ENEMY, CG.DamageType.PHYSICAL):
		for p in part["points"]:
			var bin := clampi(int((p.x + radius) / (radius * 2.0) * float(bins)), 0, bins - 1)
			top[bin] = minf(top[bin], p.y)
	var margin := radius * 0.08
	var peaks := 0
	for i in range(1, bins - 1):
		if top[i] == INF or top[i - 1] == INF or top[i + 1] == INF:
			continue
		if top[i] < top[i - 1] - margin and top[i] < top[i + 1] - margin:
			peaks += 1
	return peaks


func _aspect(id: StringName) -> float:
	var parts := Silhouettes.build_parts(id, 100.0, CG.Team.ENEMY, CG.DamageType.PHYSICAL)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for part in parts:
		for p in part["points"]:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return (hi.x - lo.x) / maxf(0.001, hi.y - lo.y)


func test_the_rat_king_and_its_rat_are_not_the_same_shape() -> void:
	# They are a pair and they are meant to be related, which is precisely the
	# condition under which two shapes drift into being one. The miniboss and its
	# chaff appear on screen together and constantly.
	var king := Silhouettes.build_parts(&"rat_king", 60.0, CG.Team.ENEMY, CG.DamageType.PHYSICAL)
	var rat := Silhouettes.build_parts(&"rat", 60.0, CG.Team.ENEMY, CG.DamageType.PHYSICAL)
	assert_ne(king.size(), rat.size(), "the Rat King and the rat build identical polygon counts")
	assert_true(_aspect(&"rat") > _aspect(&"rat_king"),
		"the rat must be the flatter of the two: the pile is tall because it is a pile")


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


## Icons drawn before the content that will use them exists.
##
## **This list breaks a genuine deadlock rather than excusing a mistake.** Art
## and content for one enemy are two commits in two files owned by two sessions,
## and each is red without the other: an icon with no action fails the test
## below, and an action with no icon fails `test_every_reachable_action_has_an
## _icon`. Whichever merges first turns the trunk red for the other. heron put
## it exactly right on #148 -- *"you cannot add an enemy to this game without one
## commit in `Scripts/Art`"* -- and that coupling is fine as long as it does not
## also mean the trunk cannot be green until both land in the same minute.
##
## **Every entry here is temporary and this list deletes itself.** The check
## below asserts the reason for each entry is STILL TRUE, so the moment the
## action reaches the registry the entry is stale and the gate says so, naming
## the line to remove. A comment saying "remove this later" rots; an assertion
## that the excuse still applies cannot.
const _ICONS_AHEAD_OF_CONTENT := {
	# heron's #148. Delete these three the same time that branch merges.
}


func test_action_icon_table_has_no_entries_for_actions_that_do_not_exist() -> void:
	# The other direction: an icon left behind after content deletes an action
	# is dead weight and, worse, evidence that the two have drifted.
	for id in ActionIcons.GLYPHS.keys():
		if _ICONS_AHEAD_OF_CONTENT.has(id):
			continue
		assert_not_null(Registry.get_action(id), "ActionIcons has an icon for %s, which the registry does not define" % id)


func test_the_icons_drawn_ahead_of_content_are_still_ahead_of_content() -> void:
	# The expiry date on the list above. Without this the exemption outlives its
	# reason, and the next icon left behind by deleted content hides inside it.
	#
	# **Collected and asserted once rather than asserted inside the loop, and
	# that is not a style choice.** The loop version made zero assertions when
	# the list was empty, and this project's gate correctly fails a test that
	# records none -- so emptying the list, which is the SUCCESSFUL end state
	# this whole mechanism exists to reach, turned the trunk red with the
	# message "it crashed part-way, or it asserts nothing". Whoever deleted the
	# last three lines would have been told they had broken something.
	#
	# Found by doing it: merging heron's branch in a scratch worktree, deleting
	# the three lines and running the gate. Reading this test would never have
	# shown it, because the bug is in the case where the loop does not run.
	var stale: Array[String] = []
	var described_nothing: Array[String] = []
	for id in _ICONS_AHEAD_OF_CONTENT:
		if not ActionIcons.GLYPHS.has(id):
			described_nothing.append(String(id))
		if Registry.get_action(id) != null:
			stale.append("%s (%s)" % [id, _ICONS_AHEAD_OF_CONTENT[id]])
	assert_eq(described_nothing, [] as Array[String],
		"_ICONS_AHEAD_OF_CONTENT names ids with no icon at all, so those entries describe nothing")
	assert_eq(stale, [] as Array[String],
		("the registry now defines these, so their icons are no longer ahead of content. "
		+ "DELETE their lines from _ICONS_AHEAD_OF_CONTENT in this file -- that is the whole fix, "
		+ "and an empty list is the correct end state rather than a problem."))


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
	# sable: added by finch on issue 99, using the mechanism this test's own
	# failure message prescribes rather than editing the assertion. Second Wind
	# is the Warrior's self-heal, replacing Directional Block. Every glyph in
	# ActionIcons is already spoken for, so the choice was share one or author
	# new art, and the art is yours rather than mine to draw. `_CROSS` is the
	# right share on this file's own rule that a glyph names what an action
	# does: both of these restore health. They are never drawn side by side --
	# they belong to different classes and no pawn can carry both.
	# **If you would rather Second Wind had its own shape, draw one and delete
	# this entry; the negative half of this test will then fail if you forget.**
	"priest_heal|warrior_second_wind": true,
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


# ---------------------------------------------------------------------------
# BLEED stack count (#130). The player: "Bleed should differentiate itself from
# poison in that it does damage less often but stacks infinitely", and the issue
# is explicit that a badge identical at one stack and at nine fails their own
# definition of done.
#
# Geometry only. Whether a five-pixel digit is legible is not testable and was
# not guessed at: Tools/StackBadgeSheet.tscn renders it at the real 17.4px and
# at 4x, and the screenshots are committed.
# ---------------------------------------------------------------------------

const _BADGE := Rect2(Vector2(10.0, 20.0), Vector2(17.4, 17.4))


func test_one_stack_draws_no_count_at_all() -> void:
	# The property that made it safe to add an argument to `draw_status` rather
	# than to write a second function: every existing call site keeps its old
	# behaviour without being edited. Eleven statuses cannot stack and a badge
	# that always carried "1" would be noise on all of them.
	assert_false(StatusIcons.shows_stack_count(1))
	assert_false(StatusIcons.shows_stack_count(0))
	assert_false(StatusIcons.shows_stack_count(-3))
	assert_true(StatusIcons.shows_stack_count(2))
	assert_true(StatusIcons.shows_stack_count(140))


func test_the_count_is_capped_at_two_digits_and_says_so() -> void:
	# The tab is about ten pixels wide on screen. A third digit is not a number,
	# it is a smudge. The cap loses real information -- BLEED stacks infinitely --
	# so it shows "99+" rather than a wrong number.
	assert_eq(StatusIcons.stack_text(2), "2")
	assert_eq(StatusIcons.stack_text(9), "9")
	assert_eq(StatusIcons.stack_text(10), "10")
	assert_eq(StatusIcons.stack_text(99), "99")
	assert_eq(StatusIcons.stack_text(100), "99+")
	assert_eq(StatusIcons.stack_text(140), "99+")


func test_the_count_never_reaches_into_the_next_badge() -> void:
	# Found by rendering a row of four: a tab overhanging to the right landed on
	# top of the neighbouring status's badge. `layout_row` uses a three pixel
	# gap, so the only safe rule is that the tab never exceeds the badge's own
	# width -- it grows upward or downward, never outward.
	for stacks in [2, 9, 10, 99, 140]:
		for size in [12.0, 17.4, 40.0, 78.0]:
			var rect := Rect2(Vector2(5.0, 5.0), Vector2(size, size))
			var tab := StatusIcons.stack_count_rect(CG.Status.BLEED, rect, stacks)
			assert_true(tab.size.x <= rect.size.x + 0.01,
				"at %d stacks and size %.1f the tab is %.1f wide against a %.1f badge" % [
					stacks, size, tab.size.x, rect.size.x])
			assert_true(tab.end.x <= rect.end.x + 0.01,
				"the tab's right edge is outside the badge at %d stacks" % stacks)


func test_the_count_never_covers_the_plate_point() -> void:
	# THE ONE THAT MATTERS, and the first version failed it.
	#
	# These plates point DOWN when harmful and UP when helpful, and
	# Assets/UI/README.md promises the player that the direction carries the same
	# information as the colour, "so it still works for a player who cannot
	# separate red from green". A tab in the bottom-right corner sits exactly on
	# a harmful plate's point and rubs it out. That is a picture replacing
	# information, it is this project's house rule, and no test or screenshot
	# review would have caught it -- I caught it by looking at the render.
	#
	# So: the tab must stay in the half of the badge AWAY from the point.
	for stacks in [2, 27, 140]:
		var harmful := StatusIcons.stack_count_rect(CG.Status.BLEED, _BADGE, stacks)
		assert_true(harmful.end.y <= _BADGE.position.y + _BADGE.size.y * 0.5,
			"a harmful badge points down and its %d-stack tab reaches y=%.1f, into the point" % [
				stacks, harmful.end.y])
		var helpful := StatusIcons.stack_count_rect(CG.Status.SHIELD, _BADGE, stacks)
		assert_true(helpful.position.y >= _BADGE.position.y + _BADGE.size.y * 0.5,
			"a helpful badge points up and its %d-stack tab reaches y=%.1f, into the point" % [
				stacks, helpful.position.y])


func test_the_count_sits_on_opposite_edges_for_harmful_and_helpful() -> void:
	# The negative half of the test above. Without it, a `stack_count_rect` that
	# always returned a tab in the middle would satisfy both assertions there for
	# neither of the right reasons.
	var harmful := StatusIcons.stack_count_rect(CG.Status.BLEED, _BADGE, 5)
	var helpful := StatusIcons.stack_count_rect(CG.Status.SHIELD, _BADGE, 5)
	assert_true(harmful.position.y < helpful.position.y,
		"harmful and helpful tabs sit at the same height; the plate direction is not being read")
	# And each overhangs its own flat edge rather than sitting wholly inside,
	# which is what keeps the glyph full size on a stacking badge.
	assert_true(harmful.position.y < _BADGE.position.y,
		"the harmful tab does not overhang the top edge, so it is eating the glyph")
	assert_true(helpful.end.y > _BADGE.end.y,
		"the helpful tab does not overhang the bottom edge, so it is eating the glyph")


func test_the_count_grows_with_the_badge() -> void:
	# A hover panel draws these much larger than a unit does. A tab sized in
	# absolute pixels would be invisible there and enormous here.
	var small := StatusIcons.stack_count_rect(CG.Status.BLEED, Rect2(Vector2.ZERO, Vector2(16.0, 16.0)), 7)
	var large := StatusIcons.stack_count_rect(CG.Status.BLEED, Rect2(Vector2.ZERO, Vector2(80.0, 80.0)), 7)
	assert_true(large.size.y > small.size.y * 4.0,
		"the tab does not scale with the badge: %.1f at 16px and %.1f at 80px" % [small.size.y, large.size.y])


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


# ---------------------------------------------------------------------------
# EquipmentIcons: one icon per item, for issue 100's equip screen.
#
# Geometry and table checks only, same reasoning as everything above -- `draw_*`
# needs a live canvas. The check these cannot make is whether two icons look
# alike, and that one is `Tools/EquipmentIconSheet.tscn`, which is the only
# instrument that has ever caught a collision on this project.
# ---------------------------------------------------------------------------

const EquipmentIcons := preload("res://Scripts/Art/EquipmentIcons.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")

const _EVERY_SLOT := [
	EquipmentDef.Slot.WEAPON, EquipmentDef.Slot.ARMOR, EquipmentDef.Slot.ACCESSORY,
]


func test_every_registered_item_has_an_icon() -> void:
	# The reason `EquipmentDef` sat unreachable for weeks is that nothing failed
	# when it was not drawn. An item added in Scripts/Content now goes red here
	# rather than shipping as a blank square on the equip screen.
	var ids := Registry.all_equipment_ids()
	assert_true(ids.size() > 0, "no items registered; this test would pass on an empty game")
	for id in ids:
		assert_true(
			EquipmentIcons.has_glyph(id),
			"item '%s' is registered but EquipmentIcons has no glyph for it" % id
		)


func test_the_icon_table_has_no_entries_for_items_that_do_not_exist() -> void:
	# The other direction. An entry for a deleted item is dead art nobody sees,
	# and it is how a table drifts away from the content it claims to describe.
	for id in EquipmentIcons.known_ids():
		assert_not_null(
			Registry.get_equipment(id),
			"EquipmentIcons draws '%s', which is not a registered item" % id
		)


func test_no_two_items_share_a_glyph() -> void:
	# The four rings deliberately share a band and differ by gem, so `glyph_for`
	# returns band-plus-gem and no two of them are equal. Anything that does come
	# out equal here is an accident.
	var seen: Dictionary = {}
	for id in EquipmentIcons.known_ids():
		var glyph: Array = EquipmentIcons.glyph_for(id)
		for other in seen.keys():
			assert_ne(
				seen[other], glyph,
				"%s and %s draw the same glyph; give one of them its own shape" % [id, other]
			)
		seen[id] = glyph


func test_the_three_slots_are_told_apart_by_shape_and_by_colour() -> void:
	# Two redundant channels, and this test exists because losing one of them is
	# silent: a player who cannot separate the rim colours still has the plate,
	# and a greyscale screenshot still shows three different outlines.
	var shapes: Array = []
	var colors: Array = []
	for slot in _EVERY_SLOT:
		var points: Array = EquipmentIcons.plate_points(slot)
		assert_false(shapes.has(points), "two slots draw the same plate outline")
		shapes.append(points)
		var c := EquipmentIcons.slot_color(slot)
		assert_false(colors.has(c), "two slots draw the same rim colour")
		colors.append(c)
	# The accessory is a circle rather than a polygon, and that is the point --
	# an n-gon here would be ActionIcons.PLATE with the corners knocked off.
	assert_true(EquipmentIcons.plate_points(EquipmentDef.Slot.ACCESSORY).is_empty())


func test_no_item_plate_is_another_icon_system_s_plate() -> void:
	# Three icon systems can be on the equip screen at once -- the item, the
	# action it grants, and the status that action applies. A glance should never
	# have to work out which system it is reading first.
	for slot in _EVERY_SLOT:
		var points: Array = EquipmentIcons.plate_points(slot)
		assert_ne(points, ActionIcons.PLATE, "an item plate is the ability plate")
		assert_ne(points, StatusIcons.PLATE_GOOD, "an item plate is the beneficial status plate")
		assert_ne(points, StatusIcons.PLATE_BAD, "an item plate is the harmful status plate")


func test_an_item_that_grants_an_action_can_draw_that_action_s_own_glyph() -> void:
	# Rule 3, and the thing #100 made true that no art had yet said: `plate_mail`
	# teaches Directional Block, and an item that changes what a pawn can DO is a
	# different kind of item from one that adds 3 STR.
	#
	# There is deliberately no second table here. The badge resolves through
	# `ActionIcons.glyph_for`, so it cannot drift from what the wind-up bar draws
	# for the same action -- which is exactly how `geyser_cleanse` came to show a
	# damage-over-time attack's icon.
	var granting := 0
	for id in Registry.all_equipment_ids():
		var item := Registry.get_equipment(id)
		for action_id in item.granted_actions:
			assert_true(
				ActionIcons.has_glyph(action_id),
				"item '%s' grants '%s', which has no icon to put in its corner badge" % [id, action_id]
			)
			granting += 1
	assert_true(granting > 0, "no item grants an action; this test would pass on content that cannot exercise it")


func test_item_glyph_geometry_stays_inside_its_own_rect() -> void:
	# A glyph escaping its box shows up as an icon bleeding into the slot beside
	# it, which reads as a rendering bug rather than as bad art. Rotated parts are
	# the ones that do it: a corner inside the unit square is not necessarily
	# inside the unit circle.
	var rect := Rect2(100.0, 40.0, 20.0, 20.0)
	var all: Array = []
	for id in EquipmentIcons.known_ids():
		all.append(EquipmentIcons.glyph_for(id))
	for slot in _EVERY_SLOT:
		var points: Array = EquipmentIcons.plate_points(slot)
		if not points.is_empty():
			all.append([{"poly": points}])
	for glyph in all:
		for part in glyph:
			for p in UIArt.glyph_points(part, rect):
				assert_true(
					rect.grow(0.01).has_point(p),
					"glyph point %s escapes its rect %s" % [p, rect]
				)


func test_the_four_rings_differ_by_colour_and_by_cut() -> void:
	# They are four rings and pretending they have four unrelated outlines would
	# be inventing a difference the content does not have. So they carry two
	# channels of their own, and losing either is silent: without the cut a
	# greyscale reader has four identical icons, without the colour a 20px reader
	# has four identical icons.
	var colors: Array = []
	var cuts: Array = []
	for id in EquipmentIcons.RING_GEMS.keys():
		var c := EquipmentIcons.gem_color(id)
		assert_false(colors.has(c), "two rings share a gem colour")
		colors.append(c)
		var cut: Array = EquipmentIcons.RING_GEMS[id]
		assert_false(cuts.has(cut), "two rings share a gem cut")
		cuts.append(cut)
	assert_eq(colors.size(), 4)


func test_item_art_name_is_the_item_id() -> void:
	assert_eq(EquipmentIcons.art_name(&"plate_mail"), &"item/plate_mail")


func test_the_equipment_replacement_instructions_match_the_real_content() -> void:
	# Assets/UI/README.md is now a document the player is expected to read and
	# use. An item added without a line there is an item whose PNG silently never
	# appears, and the artist finds out by dropping one in.
	var readme := FileAccess.get_file_as_string("res://Assets/UI/README.md")
	assert_ne(readme, "", "Assets/UI/README.md is missing")
	for id in Registry.all_equipment_ids():
		assert_true(
			readme.contains("item/%s.png" % id),
			"item '%s' is registered but Assets/UI/README.md does not list item/%s.png" % [id, id]
		)


# ---------------------------------------------------------------------------
# UIArt theming (#115): borders and backgrounds for the major elements, through
# the pipeline that already exists.
#
# These write real PNGs into Assets/UI and delete them again, the same way
# `test_a_dropped_in_png_is_found_with_no_registration` does, because the claim
# being made is about files on disk and reasoning about it proves nothing.
#
# Every one has a NEGATIVE half. With no file present these calls must produce
# exactly what the screens already build by hand -- that property is what makes
# it safe to convert nine screens at once, and a test that only checked the
# themed path would pass while the default silently changed.
# ---------------------------------------------------------------------------

const Palette := preload("res://Scripts/Core/Palette.gd")

const _THEME_SCRATCH := ["res://Assets/UI/panel.png", "res://Assets/UI/panel/scratch_element.png",
	"res://Assets/UI/background.png", "res://Assets/UI/border/scratch_element.png"]


func _write_theme_png(path: String, size: int = 12) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 1.0, 1.0, 1.0))
	assert_eq(image.save_png(path), OK, "could not write %s" % path)
	UIArt.clear_cache()


func _clear_theme_scratch() -> void:
	for path in _THEME_SCRATCH:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("res://Assets/UI/panel")
	DirAccess.remove_absolute("res://Assets/UI/background")
	DirAccess.remove_absolute("res://Assets/UI/border")
	UIArt.clear_cache()


func test_with_no_theme_files_a_panel_is_the_flat_box_the_screens_build_today() -> void:
	# The negative half, and the load-bearing one. Nine screens are meant to be
	# converted to this call, and the promise that makes it safe is that with no
	# file present nothing changes by a single pixel.
	_clear_theme_scratch()
	var style := UIArt.panel_style(&"anything", Palette.ARENA_FLOOR, Palette.ARENA_EDGE, 1, Palette.SPACE_S)
	assert_true(style is StyleBoxFlat, "with no file a panel must be the StyleBoxFlat the screens already use")
	assert_eq(style.bg_color, Palette.ARENA_FLOOR)
	assert_eq(style.border_color, Palette.ARENA_EDGE)
	assert_eq(style.border_width_left, 1)
	assert_almost_eq(style.content_margin_left, Palette.SPACE_S, 0.001)


func test_with_no_theme_files_a_background_is_the_flat_colour_rect() -> void:
	_clear_theme_scratch()
	var node := UIArt.background_node(&"anything", Palette.BACKGROUND)
	assert_true(node is ColorRect, "with no file a background must be the ColorRect the screens already use")
	assert_eq(node.color, Palette.BACKGROUND)
	node.free()


func test_a_background_never_swallows_mouse_input() -> void:
	# A background that eats clicks is a screen whose buttons stop working, and
	# that failure looks exactly like the buttons being broken rather than like
	# the theming. Both paths, because only one of them is a new node type.
	_clear_theme_scratch()
	var bare := UIArt.background_node(&"scratch_element", Palette.BACKGROUND)
	assert_eq(bare.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	bare.free()
	_write_theme_png("res://Assets/UI/background.png")
	var themed := UIArt.background_node(&"scratch_element", Palette.BACKGROUND)
	assert_eq(themed.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	themed.free()
	_clear_theme_scratch()


func test_a_background_covers_its_rect_rather_than_fitting_inside_it() -> void:
	# The one place this pipeline deliberately departs from `draw_fit`. An icon
	# that does not quite fill its box looks slightly small; a background that
	# does not quite fill its screen has bars down the sides and looks broken.
	_write_theme_png("res://Assets/UI/background.png")
	var node := UIArt.background_node(&"scratch_element", Palette.BACKGROUND)
	assert_true(node is TextureRect)
	assert_eq(node.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	assert_eq(node.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	node.free()
	_clear_theme_scratch()


func test_one_general_file_themes_every_element() -> void:
	# Drop in `panel.png` and every panel in the game is re-skinned, with no code
	# change and no per-element file. Without this a player needs nine files
	# before anything looks different.
	_write_theme_png("res://Assets/UI/panel.png")
	assert_eq(UIArt.theme_name(&"panel", &"one_element"), &"panel")
	assert_eq(UIArt.theme_name(&"panel", &"a_completely_different_element"), &"panel")
	assert_true(UIArt.panel_style(&"one_element", Palette.ARENA_FLOOR, Palette.ARENA_EDGE) is StyleBoxTexture)
	_clear_theme_scratch()


func test_a_specific_file_overrides_the_general_one_for_that_element_only() -> void:
	# And the other half: adding `panel/<element>.png` later must win for that
	# element without disturbing anything else that is already themed.
	_write_theme_png("res://Assets/UI/panel.png")
	_write_theme_png("res://Assets/UI/panel/scratch_element.png")
	assert_eq(UIArt.theme_name(&"panel", &"scratch_element"), &"panel/scratch_element")
	assert_eq(UIArt.theme_name(&"panel", &"some_other_element"), &"panel",
		"a specific override leaked onto an element it was not written for")
	_clear_theme_scratch()


func test_theme_lookup_is_silent_when_nothing_is_dropped_in() -> void:
	# The detector-stays-quiet half. A lookup that resolved to something on an
	# empty Assets/UI would theme the game with a file nobody wrote.
	_clear_theme_scratch()
	assert_eq(UIArt.theme_name(&"panel", &"scratch_element"), &"")
	assert_eq(UIArt.theme_name(&"background", &"scratch_element"), &"")
	assert_eq(UIArt.border_art_name(&"scratch_element"), &"")
	assert_eq(UIArt.border_art_name(&""), &"")


func test_a_border_resolves_the_specific_file_then_the_documented_general_one() -> void:
	# `panel_border` and not `border` as the general name, because that is what
	# Assets/UI/README.md has told the player since #81 and renaming it would
	# break a promise already made in writing.
	_clear_theme_scratch()
	_write_theme_png("res://Assets/UI/panel_border.png")
	assert_eq(UIArt.border_art_name(&"scratch_element"), &"panel_border")
	_write_theme_png("res://Assets/UI/border/scratch_element.png")
	assert_eq(UIArt.border_art_name(&"scratch_element"), &"border/scratch_element")
	assert_eq(UIArt.border_art_name(&"another_element"), &"panel_border")
	DirAccess.remove_absolute("res://Assets/UI/panel_border.png")
	_clear_theme_scratch()
	assert_eq(UIArt.border_art_name(&"scratch_element"), &"",
		"a theme file survived its own deletion")


func test_the_theming_instructions_name_every_file_the_code_looks_for() -> void:
	# Assets/UI/README.md is a document the player is expected to read and use.
	# A lookup the code performs and the README does not mention is a file that
	# would work and that nobody could know to write.
	var readme := FileAccess.get_file_as_string("res://Assets/UI/README.md")
	for name in ["panel.png", "panel_border.png", "background.png"]:
		assert_true(readme.contains(name), "Assets/UI/README.md does not mention %s" % name)
