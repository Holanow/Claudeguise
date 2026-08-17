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


## THE TEST THIS REPLACES CLAIMED SOMETHING TOP-EDGE GEOMETRY CANNOT SAY, AND
## THE CLAIM IS WITHDRAWN HERE RATHER THAN RE-THRESHOLDED.
##
## It was called `test_the_rat_king_reads_as_more_than_one_animal` and it
## asserted that the Rat King scores more outline peaks than `the_warden`,
## `ghoul` and `brute`. It passed. It was measuring `build_parts` -- the
## POLYGONS -- and `rat_king`, `the_warden` and `ghoul` all have PNGs in
## `Assets/Units/`, so for three of the four shapes in that comparison the thing
## measured is dead code the game never renders. Identical to the `fill_ratio`
## defect in `BADGE-LEGIBILITY.md`; that one was fixed and nobody swept the file
## for a second instance.
##
## Pointed at the drawn art, the comparison collapses. Measured over all
## nineteen shapes, crests and the shallowest valley in canvas px at radius 200:
##
##     rat_king       3   31        goblin          3   17
##     the_warden     2   17        warrior         3   50
##     ghoul          2   50        geysermancer    3   83
##     brute          2   71        goblin_archer   3   17
##
## **Four single-creature shapes still in the game score three.** A pawn with a head, an ear and a
## raised weapon has the same top-edge signature as a pile of three animals,
## because a top edge cannot tell a lobe from a creature. The old test's margin
## came from the Rat King's polygon having many vertices near its top, which is
## a fact about how it was authored rather than about how it reads.
##
## So "reads as many" is **not measurable here** and nothing below asserts it.
## `Tools/RatKingSheet.tscn` and a screenshot of a real fight are the instrument
## for that claim, and they are the reason both are committed.
##
## What IS measurable, and is a direct statement of the design rather than a
## proxy for it: the back is three humps with sky between them.
func test_the_rat_kings_back_is_three_humps_and_not_a_dome() -> void:
	var crests := _peaks(&"rat_king")
	assert_eq(crests, 3,
		("the Rat King's back has %d crests, not 3; the humps have fused into a dome, "
		+ "and one dome is one animal at any size") % crests)


func test_the_rat_kings_valleys_keep_their_depth() -> void:
	# The margin, guarded separately per this project's own rule, and moved onto
	# the number that actually has headroom. A crest COUNT has none: three is the
	# most any shape in the game scores, so the old `>= 4` was not a margin, it
	# was unreachable.
	#
	# **This guards a failure mode I hit while drawing the sprite, not a
	# hypothetical.** The outline pass is 8-connected, so it climbs a valley wall
	# diagonally from both sides; authored one column wide, valleys at y11 and y9
	# read back off the finished PNG as y6 and y4 and the scallop was simply gone.
	# The crest count went to 1 and it was right to. Three-column valleys survive.
	#
	# Measured at 31 canvas px at radius 200, against the-warden's 17 and
	# goblin's 17. The floor is 20: it fires while the shape still passes, and
	# the bridging failure above puts it near zero.
	var depth := _shallowest_valley(&"rat_king")
	assert_true(depth >= 20.0,
		("the Rat King's shallowest valley is %.0f px deep at radius 200, down from a measured 31. "
		+ "The backs are merging -- check whether the outline pass has bridged a valley narrower "
		+ "than three columns.") % depth)


func test_the_crest_detector_can_tell_a_dome_from_a_range() -> void:
	# The detector, verified against hand-made profiles rather than trusted,
	# because everything above is a number it produced. The per-bin version this
	# replaces would have scored BOTH of these zero: it asked whether one bin
	# sits lower than both its immediate neighbours by the margin, which holds
	# for a sparse profile of polygon vertices and never for pixel columns, where
	# adjacent bins usually read the same column and compare equal.
	#
	# It failed CLOSED -- zero for every shape, the Rat King included -- so
	# repointing the old test at real art without replacing the detector would
	# have looked like the sprite failing.
	var dome := PackedFloat32Array([0.0, -40.0, -80.0, -100.0, -80.0, -40.0, 0.0])
	assert_eq(_crests(dome, 16.0), 1, "a single dome must score one crest")

	var range_of_three := PackedFloat32Array([
		0.0, -60.0, 0.0, -100.0, -20.0, -80.0, 0.0])
	assert_eq(_crests(range_of_three, 16.0), 3, "three humps with valleys between them must score three")

	# And it must not find a crest in noise smaller than the margin.
	var rough_flat := PackedFloat32Array([-50.0, -54.0, -48.0, -55.0, -47.0, -52.0])
	assert_eq(_crests(rough_flat, 16.0), 1, "wobble under the margin is not a hump")


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


## **This read `Silhouettes.build_parts` and was therefore counting humps on art
## the game does not draw.** `rat_king`, `the_warden` and `ghoul` all have PNGs
## in `Assets/Units/`, so for those the polygons are dead code -- the test could
## not have failed for the shape a player actually meets, whatever happened to
## it. It is the identical defect the correction note in `BADGE-LEGIBILITY.md`
## records for `fill_ratio`; that one was fixed and nobody swept the file for a
## second instance, and this was it.
##
## `Silhouettes.top_profile` takes the same two paths `draw_unit` does, in the
## same order, and reads real pixel columns for a shape with a sprite.
func _peaks(id: StringName) -> int:
	var radius := 200.0
	return _crests(Silhouettes.top_profile(id, radius, CG.Team.ENEMY, 40), radius * 0.08)


## How many crests the top edge has, where a crest is separated from the next by
## a valley at least `margin` deep. Prominence, not a per-bin comparison.
##
## **The per-bin version silently stopped working the moment the profile became
## dense, and it failed CLOSED -- it reported zero for every shape, including
## the Rat King.** It asked whether one bin sits lower than both its immediate
## neighbours by `margin`; that holds for a sparse profile of polygon vertices
## and never holds for pixel columns, where 40 bins across a 26-pixel sprite
## means adjacent bins usually read the SAME column and compare equal. A crest
## six pixels tall scored zero.
##
## Worth stating plainly because it is the more useful half of what this file
## learned today: the old detector was not merely measuring dead art, it was
## measuring it in a way that could not survive being pointed at the real thing.
static func _crests(top: PackedFloat32Array, margin: float) -> int:
	var out := 0
	for i in _extremes(top, margin).size():
		if i % 2 == 0:
			out += 1
	return out


## The alternating crest, valley, crest, ... heights of a top edge, in the same
## units the profile is in. Even indices are crests, odd ones valleys.
static func _extremes(top: PackedFloat32Array, margin: float) -> Array[float]:
	# Gaps are gaps, not floors. A polygon profile is sampled along edges and
	# still has them outside the shape; a sprite profile has none.
	var vals: Array[float] = []
	for v in top:
		if v < INF:
			vals.append(v)
	if vals.is_empty():
		return [] as Array[float]
	var out: Array[float] = []
	var rising := true       # rising = the outline is going UP, so y is falling
	var extreme := vals[0]
	for v in vals:
		if rising:
			if v > extreme + margin:
				out.append(extreme)  # that was a crest, and we are off it now
				rising = false
				extreme = v
			elif v < extreme:
				extreme = v
		else:
			if v < extreme - margin:
				out.append(extreme)  # that was a valley
				rising = true
				extreme = v
			elif v > extreme:
				extreme = v
	if rising:
		out.append(extreme)  # the last crest has no valley after it
	return out


## How deep the SHALLOWEST valley on a top edge is, measured against the lower
## of the two crests beside it. Zero when there is no valley at all.
func _shallowest_valley(id: StringName) -> float:
	var radius := 200.0
	var ext := _extremes(Silhouettes.top_profile(id, radius, CG.Team.ENEMY, 40), radius * 0.08)
	var shallowest := INF
	var i := 1
	while i < ext.size() - 1:
		# y grows downward, so a valley's depth is how far BELOW its neighbours
		# it sits, and the honest number is against the nearer of the two.
		shallowest = minf(shallowest, ext[i] - maxf(ext[i - 1], ext[i + 1]))
		i += 2
	return 0.0 if shallowest == INF else shallowest


func _aspect(id: StringName) -> float:
	var parts := Silhouettes.build_parts(id, 100.0, CG.Team.ENEMY, CG.DamageType.PHYSICAL)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for part in parts:
		for p in part["points"]:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return (hi.x - lo.x) / maxf(0.001, hi.y - lo.y)


## Fraction of its own nominal box a shape's drawn width actually covers.
##
## **This used to read `Silhouettes.build_parts` and it was measuring the wrong
## thing.** Ten shapes have real PNGs in `Assets/Units/`, and for those the
## polygons in `Silhouettes` are dead code the game never renders -- so the
## number this produced was a fact about art nobody sees. It goes through
## `Silhouettes.fill_ratio`, which takes the same two paths `draw_unit` does, in
## the same order. See the correction note in `BADGE-LEGIBILITY.md`.
func _fill_fraction(id: StringName) -> float:
	return Silhouettes.fill_ratio(id, CG.Team.ENEMY).x


func test_no_silhouette_is_drawn_tiny_inside_its_own_footprint() -> void:
	# Measured for PLAYTEST-FRESH-2, whose headline is that units are too small
	# to identify. The floor fails nothing today and fires on a shape drawn
	# smaller than any that has ever shipped.
	#
	# This is NOT a claim that any shape should be wider. A goblin is a small
	# hunched creature and that is what the shape is. It is a claim that nobody
	# should add a shape that occupies a third of the space the game reserves for
	# it, because the decoration around it is sized from the reservation.
	#
	# The floor stays at 0.5 across the correction from polygons to real art, and
	# that is a coincidence worth writing down rather than a threshold left
	# alone: the polygon path's worst was the goblin at 0.56, the real art's
	# worst is `priest.png` at exactly 0.50 -- twelve opaque columns of a
	# twenty-four wide file. It sits ON the floor, so the next shape drawn any
	# narrower goes red immediately.
	for id in CLASS_SHAPES + UNUSED_SHAPES + AHEAD_OF_CONTENT_SHAPES + [&"goblin", &"goblin_archer", &"ghoul", &"the_warden", &"cultist"]:
		var fill := _fill_fraction(id)
		assert_true(fill >= 0.5,
			"%s is drawn at %.2f of its own footprint width; its bar, badges and impact ring are sized from the full footprint" % [id, fill])


func test_fill_ratio_reads_the_real_art_and_not_the_dead_polygons() -> void:
	# The regression guard for the defect above, and the reason it is possible to
	# state as an assertion: for a shape with a PNG, the two paths disagree.
	# `warrior` has `Assets/Units/warrior.png`, so `draw_unit` draws the texture
	# and `build_parts` is never reached.
	#
	# If somebody deletes the PNGs this goes red rather than silently passing --
	# which is correct: the whole point is that the measurement follows the art.
	assert_true(UnitArt.has_art(&"warrior", CG.Team.PLAYER),
		"this test measures the texture path; without a PNG for warrior it measures nothing")

	var from_art := Silhouettes.fill_ratio(&"warrior", CG.Team.PLAYER)
	var parts := Silhouettes.build_parts(&"warrior", 100.0, CG.Team.PLAYER, CG.DamageType.PHYSICAL)
	var lo := INF
	var hi := -INF
	for part in parts:
		for p in part["points"]:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
	var from_polygons := (hi - lo) / 200.0
	assert_true(absf(from_art.x - from_polygons) > 0.05,
		"fill_ratio returned the polygon width (%.2f) for a shape that draws a texture" % from_polygons)


func test_fill_ratio_ignores_a_sprites_transparent_margin() -> void:
	# The trap this exists to close, and the reason `opaque_rect` scans pixels
	# instead of reading `get_width`. Pixel art carries margin: `siege_master.png`
	# is a 24x14 file with only 20x8 of it opaque. A caller that moved off the
	# collision radius and onto the file dimensions would fix part of #190 and
	# look like it had fixed all of it.
	assert_true(UnitArt.has_art(&"siege_master", CG.Team.PLAYER),
		"this test measures the texture path; without a PNG for siege_master it measures nothing")
	var tex := UnitArt.texture_for(&"siege_master", CG.Team.PLAYER)
	var file_fraction := Vector2(tex.get_width(), tex.get_height()) / maxf(tex.get_width(), tex.get_height())
	var opaque := UnitArt.opaque_fraction(tex)
	assert_true(opaque.y < file_fraction.y - 0.1,
		"opaque_fraction returned the file's height (%.2f), margin included" % file_fraction.y)
	# And the extent must agree with the fraction, or the two answers drift.
	var extent := Silhouettes.drawn_extent(&"siege_master", 100.0, CG.Team.PLAYER)
	assert_true(absf(extent.size.y / 200.0 - opaque.y) < 0.01,
		"drawn_extent and opaque_fraction disagree about the same sprite")


func test_a_fully_transparent_sprite_does_not_collapse_to_nothing() -> void:
	# The negative case, and it is not hypothetical: the drop-in pipeline takes
	# whatever PNG is on disk. A zero-size extent would make every bar sized from
	# it vanish, which reads as the UI being broken rather than as the art being
	# blank. The fallback is the whole file.
	var image := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var tex := ImageTexture.create_from_image(image)
	assert_eq(UnitArt.opaque_fraction(tex), Vector2(1.0, 0.5),
		"a blank sprite must fall back to its file box, not to a zero-size extent")


func test_the_footprint_check_would_catch_a_shape_drawn_too_small() -> void:
	# The negative half. A floor nobody has proved can fire is furniture, and
	# this project has shipped exactly that before -- a detector with sixteen
	# passing tests that could never go red.
	#
	# `_unknown_parts` is the fallback drawn for a shape id nothing defines, and
	# it is deliberately a full-size marker, so it passes. The failing case is
	# built here rather than added to the roster: a real shape drawn at a third
	# scale.
	assert_true(_fill_fraction(&"definitely_not_a_shape") >= 0.5,
		"the unknown-shape fallback should fill its own footprint")
	var lo := INF
	var hi := -INF
	for p in [Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.3)]:
		lo = minf(lo, p.x * 100.0)
		hi = maxf(hi, p.x * 100.0)
	assert_false((hi - lo) / 200.0 >= 0.5,
		"a shape spanning 0.3 of the unit box must fail the floor, or the floor checks nothing")


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


func test_a_mirrored_sprite_is_drawn_in_the_same_place() -> void:
	# Issue 241. `UnitArt.draw` mirrored by negating the drawn width *before*
	# building the rect, which put the left edge at `center.x + width / 2`: every
	# left-facing unit was drawn one full drawn width beside itself, 65px for the
	# Warden. A negative-width `Rect2` mirrors in place and does not move, so the
	# negation belongs on the rect and not on the size that positions it.
	#
	# Arithmetic, not pixels, and deliberately: the gate is headless, headless
	# uses the dummy renderer, and a rasterising check there reads back nothing
	# and reports a silent skip. `Tools/FacingInk.gd` is the rasterising half and
	# is run by hand. This half is the one that can fail in CI.
	for id in Silhouettes.shape_ids():
		for team in [CG.Team.PLAYER, CG.Team.ENEMY]:
			var tex := UnitArt.texture_for(id, team)
			if tex == null:
				continue
			var right := UnitArt.signed_rect(tex, 33.0, false, Vector2(100.0, 40.0))
			var left := UnitArt.signed_rect(tex, 33.0, true, Vector2(100.0, 40.0))
			assert_true(left.size.x < 0.0, "%s is not mirrored when it faces left" % id)
			# NOT `left.abs()`. `Rect2.abs()` normalises by moving `position`
			# left by the width; `draw_texture_rect` does not -- it keeps
			# `position` and inks rightward. The engine's rule is the one that
			# decides where the pixels land, and it is why this bug existed.
			assert_eq(left.position, right.position,
				"%s moves when it is mirrored: %s vs %s" % [id, left.position, right.position])
			assert_eq(left.size.x, -right.size.x, "%s changes width when mirrored" % id)
			assert_eq(right.get_center(), Vector2(100.0, 40.0),
				"%s is not drawn on the centre it was given" % id)


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
	#
	# **This test is necessary and it is nowhere near sufficient, which is worth
	# stating where the next person reads it.** It compares the arrays for
	# equality, so it only ever catches a copy-paste. bleed and burn passed it
	# for months while sharing 98% of their pixels, because a droplet and a
	# flame are different arrays and the same picture. The test below is the one
	# that would have caught that.
	var seen: Array = []
	for s in _every_status():
		var g: Array = StatusIcons.GLYPHS[s]
		assert_false(seen.has(g), "CG.Status.%s reuses another status's glyph" % CG.Status.keys()[s])
		seen.append(g)


## How much of a glyph's own box each of two glyphs covers differently, sampled
## on a grid. A poor man's rasteriser, in pure GDScript, so the property can be a
## test rather than a tool somebody remembers to run.
##
## `Geometry2D.is_point_in_polygon` does the real work for filled parts; dots and
## strokes are distance tests. It is coarse on purpose -- badges are 17 pixels,
## so a 24x24 sample is finer than the thing it models.
func _glyph_coverage(glyph: Array, grid: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(grid * grid)
	for gy in grid:
		for gx in grid:
			var p := Vector2(
				(float(gx) + 0.5) / float(grid) * 2.0 - 1.0,
				(float(gy) + 0.5) / float(grid) * 2.0 - 1.0)
			var hit := 0
			for part in glyph:
				var rot := float(part.get("rot", 0.0))
				var q := p.rotated(-rot)
				if part.has("poly"):
					var poly := PackedVector2Array()
					for v in part["poly"]:
						poly.append(Vector2(v[0], v[1]))
					if Geometry2D.is_point_in_polygon(q, poly):
						hit = 1
				elif part.has("dot"):
					var d: Array = part["dot"]
					if q.distance_to(Vector2(d[0], d[1])) <= float(d[2]):
						hit = 1
				elif part.has("arc"):
					var a: Array = part["arc"]
					var w: float = float(part.get("w", 0.18)) * 0.5
					if absf(q.distance_to(Vector2(a[0], a[1])) - float(a[2])) <= w:
						hit = 1
				elif part.has("line"):
					var pts: Array = part["line"]
					var w2: float = float(part.get("w", 0.18)) * 0.5
					for i in range(pts.size() - 1):
						var s := Vector2(pts[i][0], pts[i][1])
						var e := Vector2(pts[i + 1][0], pts[i + 1][1])
						if Geometry2D.get_closest_point_to_segment(q, s, e).distance_to(q) <= w2:
							hit = 1
				if hit == 1:
					break
			out[gy * grid + gx] = hit
	return out


func _glyph_difference(a: PackedByteArray, b: PackedByteArray) -> float:
	var differing := 0
	for i in a.size():
		if a[i] != b[i]:
			differing += 1
	return float(differing) / float(a.size())


func test_no_two_status_glyphs_are_the_same_picture() -> void:
	# THE TEST THAT WOULD HAVE CAUGHT BLEED AND BURN, and the reason it exists is
	# that the header of StatusIcons.gd asserted "no two share an outline" for
	# months and it was false. A droplet and a flame are different arrays and the
	# same picture; measured on screen they disagreed on 2.1% of their pixels,
	# flat from 12px to 32px.
	#
	# The full measurement is `Tools/BadgeLegibility.tscn`, which renders and
	# compares real pixels. This is its cheap shadow: a grid sample of the glyph
	# alone, no plate, no rim, no rendering. It cannot replace the tool -- it
	# knows nothing about how much of the badge the glyph occupies -- but it
	# guards the one thing the tool found, and it runs in the gate.
	#
	# Only same-category pairs are checked, because rim colour and plate
	# direction already separate harmful from helpful and no glyph has to.
	var grid := 24
	var coverage := {}
	for s in _every_status():
		coverage[s] = _glyph_coverage(StatusIcons.GLYPHS[s], grid)

	var worst := 1.0
	var worst_pair := ""
	for a in _every_status():
		for b in _every_status():
			if a >= b or CG.is_harmful(a) != CG.is_harmful(b):
				continue
			var d := _glyph_difference(coverage[a], coverage[b])
			if d < worst:
				worst = d
				worst_pair = "%s/%s" % [CG.Status.keys()[a], CG.Status.keys()[b]]
	# Measured after the #130 rework: the closest same-category glyph pair
	# differs on about a quarter of its own box. The floor is set well under
	# that so ordinary redrawing does not trip it, and well over the 6% the old
	# droplet-and-flame pair scored on this same measure.
	assert_true(worst > 0.12,
		("the closest same-category glyph pair is %s at %.1f%% of their own box. "
		+ "Two badges that similar are one badge on a 17px unit -- redraw one, "
		+ "and re-run Tools/BadgeLegibility.tscn for the on-screen number.") % [
			worst_pair, worst * 100.0])


func test_the_glyph_similarity_detector_actually_fires() -> void:
	# A detector shipped without this is the failure mode this project has
	# written down: sixteen tests asserting a warning is well-formed when it
	# fires, none asserting it fires at all. Feed it the exact pair that started
	# this -- a droplet and the flame it was indistinguishable from -- and assert
	# it would have caught them.
	var droplet := [{"poly": [
		[0.0, -0.8], [0.42, -0.05], [0.42, 0.3], [0.18, 0.65],
		[-0.18, 0.65], [-0.42, 0.3], [-0.42, -0.05]]}]
	var flame: Array = StatusIcons.GLYPHS[CG.Status.BURN]
	var d := _glyph_difference(_glyph_coverage(droplet, 24), _glyph_coverage(flame, 24))
	assert_true(d <= 0.12,
		"the old droplet scores %.1f%% against the flame, above the floor -- this detector is inert" % [d * 100.0])
	# And the negative half: the shape that REPLACED it must clear the floor, or
	# the detector is simply rejecting everything.
	var slash: Array = StatusIcons.GLYPHS[CG.Status.BLEED]
	var d2 := _glyph_difference(_glyph_coverage(slash, 24), _glyph_coverage(flame, 24))
	assert_true(d2 > 0.12,
		"the replacement slash scores %.1f%% against the flame, so it is no better" % [d2 * 100.0])


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
	# heron's #162. Delete this one the same time that branch merges.
	# heron's #148. Delete these three the same time that branch merges.
	# heron's #192, the Rat King. Delete this line when that branch merges --
	# the test below names it for you.
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


const IconsOverlay := preload("res://Tools/IconsOverlay.gd")
const BattleViewScript := preload("res://Scripts/UI/BattleView.gd")
const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")


func test_the_diagnostic_harness_draws_badges_at_the_size_the_game_does() -> void:
	# Tools/IconsOverlay.gd is the harness every judgement about these badges has
	# been made on, including a fresh-eyes playtest that called them "invisible
	# at 1x".
	#
	# **This test has already failed to do its job once, and the way it failed is
	# the point.** It hardcoded 14.0 while the game drew 17.4; that was fixed by
	# comparing the harness against `UnitViewScript.STATUS_BADGE_SIZE`. Then #190
	# made the badge scale with the drawn body, `STATUS_BADGE_SIZE` became the
	# ceiling of a clamp almost nothing reaches, and this test went on passing
	# while the harness drew badges at TWICE the size the game did -- because
	# both sides of the assertion read the same stale constant.
	#
	# So it now compares against `status_badge_size`, the function the screen
	# calls, at a real unit's real radius. An assertion whose two sides can go
	# stale together is not a guard.
	var scale: float = BattleViewScript.compute_layout(Vector2(1280.0, 720.0))["scale"].x
	var radius := 11.0 * UnitViewScript.DISPLAY_SCALE
	assert_almost_eq(
		IconsOverlay.badge_px(&"goblin", CG.Team.ENEMY, radius, scale),
		UnitViewScript.status_badge_size(&"goblin", CG.Team.ENEMY, radius) * scale, 0.001,
		"the harness draws badges at a different size from UnitView")
	assert_almost_eq(IconsOverlay.icon_px(scale), UnitViewScript.WIND_UP_ICON_SIZE * scale, 0.001,
		"the harness draws wind-up icons at a different size from UnitView")

	# The negative half, and it is the half that was missing. A harness reading a
	# single constant cannot vary between a goblin and the Warden; the game's
	# does. If badge_px ever goes back to returning one number for every unit,
	# these two collapse to the same value and this fires.
	var warden_radius := 30.0 * UnitViewScript.DISPLAY_SCALE
	assert_true(
		IconsOverlay.badge_px(&"the_warden", CG.Team.ENEMY, warden_radius, scale)
			> IconsOverlay.badge_px(&"goblin", CG.Team.ENEMY, radius, scale) + 1.0,
		"badge_px returns the same size for a goblin and the Warden, so it is reading a constant again")
	# And it must not have drifted back to the pre-#190 ceiling, which is what it
	# silently returned for every unit for the whole of #190's life.
	assert_true(
		absf(IconsOverlay.badge_px(&"goblin", CG.Team.ENEMY, radius, scale)
			- UnitViewScript.STATUS_BADGE_SIZE * scale) > 1.0,
		"badge_px is back at STATUS_BADGE_SIZE, the clamp ceiling rather than the drawn size")


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


func test_the_status_badge_instructions_match_the_real_statuses() -> void:
	# **This test exists because a rename slipped past every check in the file.**
	#
	# ENRAGE became TAUNTED in `CG.Status`. The enum moved, the badge was
	# redrawn, the glossary sentence was rewritten -- and `Assets/UI/README.md`
	# went on telling the player to drop in `status/enrage.png`, a filename
	# `StatusIcons.art_name` has not resolved since the rename. Drop that file in
	# and nothing happens, silently, which is the worst failure this pipeline
	# has: the whole promise of the folder is "no code change, it just works".
	# SUSTAINING was added and never listed at all, the same defect from the
	# other direction.
	#
	# Every other drop-in table here is checked against the code that reads it.
	# This one was not, so it was the one that rotted. Asked as "does the code's
	# own lookup name appear", never as a hand-typed list -- a list typed here
	# would rot in exactly the same way and agree with itself while doing it.
	var readme := FileAccess.get_file_as_string("res://Assets/UI/README.md")
	assert_ne(readme, "", "Assets/UI/README.md is missing")
	for status in CG.Status.values():
		var name := "%s.png" % StatusIcons.art_name(status)
		assert_true(
			readme.contains(name),
			"CG.Status.%s draws a badge but Assets/UI/README.md does not list %s" % [
				CG.Status.keys()[status], name]
		)


func test_the_ability_icon_instructions_match_the_real_content() -> void:
	# The same check for the action table, which had drifted further: seven of
	# the thirty-four actions the registry defines were missing from it --
	# brute_slam, geyser_cleanse, geyser_spout, rat_bite, stalker_dart,
	# stalker_mark and warrior_second_wind.
	#
	# The README already claimed "this list is checked by a test", and that was
	# false. The nearby test walks the registry against `ActionIcons.GLYPHS`,
	# never against this file, so the sentence described a check that did not
	# exist. It does now.
	#
	# Registry-driven, so an action added tomorrow fails here rather than at the
	# moment an artist drops in a PNG that never appears.
	var readme := FileAccess.get_file_as_string("res://Assets/UI/README.md")
	assert_ne(readme, "", "Assets/UI/README.md is missing")
	var checked := 0
	for id in Registry.all_action_ids():
		var name := "%s.png" % ActionIcons.art_name(id)
		assert_true(
			readme.contains(name),
			"action '%s' is registered but Assets/UI/README.md does not list %s" % [id, name]
		)
		checked += 1
	assert_true(checked > 0, "no actions checked; this test would pass on an empty game")


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


## The general names, and the gap that let the README lie twice about the same
## table.
##
## The check below this one compares the README's SPECIFIC names
## (`panel/inspect.png`) against call sites. Nothing checked the general ones,
## so `panel.png` sat in the README promising to re-skin "every panel, card,
## tooltip and chip" while `UIArt.panel_style` had zero call sites in
## `Scripts/` -- the same defect as #237, in the same file, undetected after
## #237 was fixed because #237's instrument could not see this half. Issue #268.
##
## A drop-in with no caller is the worst shape a defect takes here: the file
## sits on disk looking correct, the game never reads it, and nothing goes red.
## Prose saying so rots -- this section of the README was prose for weeks.
const _GENERAL_THEME_READERS := {
	"panel.png": ["panel_style"],
	"panel_border.png": ["draw_border"],
	"background.png": ["background_node", "draw_background"],
}


func test_every_general_theme_file_the_readme_promises_has_a_call_site() -> void:
	var readme := FileAccess.get_file_as_string("res://Assets/UI/README.md")
	var promised := _readme_general_theme_files(readme)
	assert_eq(promised.size(), _GENERAL_THEME_READERS.size(),
		("Assets/UI/README.md's general theme table and this test's function map " +
		"disagree: promised %s, mapped %s. A general name added to the README " +
		"needs the UIArt function that resolves it named here, or it is promised " +
		"and unchecked.") % [promised, _GENERAL_THEME_READERS.keys()])
	for name in promised:
		assert_true(_GENERAL_THEME_READERS.has(name),
			"Assets/UI/README.md promises %s and this test does not know what reads it" % name)
		var callers := _ui_files_calling_any(_GENERAL_THEME_READERS[name])
		assert_false(callers.is_empty(),
			("Assets/UI/README.md promises %s re-skins the game, and no screen under " +
			"Scripts/UI calls %s. Dropping that file in would do nothing, silently.") % [
				name, " or ".join(_GENERAL_THEME_READERS[name])])


## The general (unfoldered) `<name>.png` cells of the README's theming table.
## Parsed, not typed, for the reason the specific list is parsed: a hand-typed
## copy of a list in another file agrees with the mistake it exists to catch.
func _readme_general_theme_files(readme: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string("\\| `([a-z_]+\\.png)` \\|")
	for m in re.search_all(readme):
		var name := m.get_string(1)
		if not out.has(name):
			out.append(name)
	out.sort()
	return out


## Which `.gd` files under `Scripts/UI` call any of `functions` on `UIArt`.
func _ui_files_calling_any(functions: Array) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://Scripts/UI")
	assert_true(dir != null, "Scripts/UI is unreadable, so this test can only report a false pass")
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("res://Scripts/UI/%s" % file)
		for fn in functions:
			if text.contains("UIArt.%s(" % fn):
				out.append(file)
				break
	out.sort()
	return out


## The other direction, and it is the one this project has already paid for
## twice. The test above asks whether the README mentions the names the code
## reads. It cannot see the opposite mistake: a name the README *prints* that no
## call site ever asks for. A file dropped in under such a name does nothing,
## silently, and looks perfectly correct sitting on disk. `status/enrage.png`
## was exactly this after the ENRAGE -> TAUNTED rename, and `background/menu.png`
## was exactly this until now -- it named a main menu the game does not have.
##
## Reproduced by rendering before this was written, not by reading: a real
## yellow-cornered `Assets/UI/border/arena.png` was dropped in and the arena
## frame kept the green corners of the general `panel_border.png`, because
## `ArenaFloor` passes no element name. `Screenshots/theme_dropin_*.png`.
##
## So the README carries a machine-checked list of which of its own names are
## not wired up yet, and this compares that list against the call sites. It goes
## red the moment issue #237 wires one, naming the line to delete.
func test_no_specific_theme_name_the_readme_prints_is_a_name_nothing_asks_for() -> void:
	var readme := FileAccess.get_file_as_string("res://Assets/UI/README.md")
	var documented := _readme_specific_theme_elements(readme)
	assert_true(documented.size() >= 3,
		"Assets/UI/README.md stopped naming specific theme files; this check now measures nothing")
	var live := _element_names_call_sites_ask_for(documented)
	var pending: Array[String] = []
	for name in documented:
		if not live.has(name):
			pending.append(name)
	pending.sort()
	assert_eq(_readme_pending_note(readme), ", ".join(pending),
		("Assets/UI/README.md's pending list and Scripts/UI's real call sites disagree. " +
		"Every name the README prints under `Assets/UI/<kind>/<name>.png` must either be " +
		"passed as an element name by a screen, or be listed in the README's pending " +
		"comment. Issue #237 is the wiring."))
	if pending.is_empty():
		assert_false(readme.contains("Not wired up yet"),
			"every theme name resolves now, so the README's 'Not wired up yet' section is a lie in the other direction")


## Every `Assets/UI/<panel|border|background>/<name>.png` the README prints, as
## element names. Parsed rather than typed: a hand-typed copy of a list in
## another file is two artifacts by one author, which is how a test ends up
## agreeing with the mistake it exists to catch.
func _readme_specific_theme_elements(readme: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string("Assets/UI/(?:panel|border|background)/([a-z_]+)\\.png")
	for m in re.search_all(readme):
		var name := m.get_string(1)
		if not out.has(name):
			out.append(name)
	out.sort()
	return out


## Which of `candidates` a screen really asks for. A `.gd` under `Scripts/UI`
## that both imports `UIArt` and contains the literal `&"<name>"` is asking for
## it; nothing else in this game has a reason to hold these strings, checked by
## grep before this was written.
func _element_names_call_sites_ask_for(candidates: Array[String]) -> Dictionary:
	var live := {}
	var dir := DirAccess.open("res://Scripts/UI")
	assert_true(dir != null, "Scripts/UI is unreadable, so this test can only report a false pass")
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("res://Scripts/UI/%s" % file)
		if not text.contains("UIArt."):
			continue
		for name in candidates:
			if text.contains('&"%s"' % name):
				live[name] = true
	return live


## The README's own statement of which of its names do not work yet, or "" when
## it makes no such claim.
func _readme_pending_note(readme: String) -> String:
	var re := RegEx.create_from_string("<!-- pending: ([^>]*) -->")
	var m := re.search(readme)
	return "" if m == null else m.get_string(1).strip_edges()
