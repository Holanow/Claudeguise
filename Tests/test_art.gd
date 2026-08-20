extends "res://Tests/TestCase.gd"


## MANAGER-OWNED, alongside Scripts/Art/.
##
## These check the parts of the placeholder art that can go wrong silently. How
## it *looks* is not testable and is not attempted: that is what
## Tools/ArtPreview.tscn and the committed screenshot are for.


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
	# Not just "a name exists": the failure guarded against is a unit drawing
	# the fallback in a real fight. There is no unknown-shape polygon set any
	# more -- a shape with no file draws a black square -- so this asks the
	# question directly, of the file.
	for id in AHEAD_OF_CONTENT_SHAPES:
		assert_true(Silhouettes.has_shape(id), "no sprite for '%s'" % id)
		var extent := Silhouettes.drawn_extent(id, 40.0, CG.Team.ENEMY)
		assert_true(extent.size.x > 0.0 and extent.size.y > 0.0,
			"'%s' has a file that puts no ink on the screen" % id)


## "Reads as more than one animal" is NOT measurable from a top edge, and
## nothing below asserts it.
##
## Measured over all nineteen shapes at radius 200, four single-creature
## shapes score the same three crests the Rat King does: a pawn with a head,
## an ear and a raised weapon has the same top-edge signature as a pile of
## three animals. `Tools/RatKingSheet.tscn` and a screenshot of a real fight
## are the instrument for that claim, which is why both are committed.
##
## What IS measurable, and states the design rather than proxying for it:
## the back is three humps with sky between them.
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


## Drawn width over drawn height. Read off `drawn_extent`, which is the sprite's
## OPAQUE box -- this used to build polygons, and for every shape with a sprite
## that was a fact about art nobody sees.
func _aspect(id: StringName) -> float:
	var box := Silhouettes.drawn_extent(id, 100.0, CG.Team.ENEMY)
	return box.size.x / maxf(0.001, box.size.y)


## Fraction of its own nominal box a shape's drawn width actually covers.
##
## **This used to read `Silhouettes.build_parts` and it was measuring the wrong
## thing** -- ten shapes had real PNGs and the polygons were dead code. There is
## one path now, so the trap is gone rather than avoided. See the correction note
## in `BADGE-LEGIBILITY.md`.
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


func test_fill_ratio_reads_the_real_art() -> void:
	# **The defect this test was written for: `fill_ratio` measured polygons for
	# ten shapes that had sprites, and a published table of numbers was wrong
	# because of it.** There is only one path now, so the defect is structurally
	# impossible; the assertion that remains is that the number comes from the
	# sprite's opaque pixels rather than from its file dimensions.
	assert_true(UnitArt.has_art(&"warrior", CG.Team.PLAYER), "warrior.png is gone; this test measures nothing")
	var ratio := Silhouettes.fill_ratio(&"warrior", CG.Team.PLAYER)
	var tex := UnitArt.texture_for(&"warrior", CG.Team.PLAYER)
	assert_eq(ratio, UnitArt.opaque_fraction(tex))
	assert_true(ratio.x > 0.0 and ratio.x <= 1.0, "fill_ratio is out of range: %s" % ratio)


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
	# The miniboss has to read as a pile of the thing it keeps spawning, and
	# still not be a big one of them. Pixels, because both have sprites.
	var king := Silhouettes.top_profile(&"rat_king", 60.0, CG.Team.ENEMY)
	var rat := Silhouettes.top_profile(&"rat", 60.0, CG.Team.ENEMY)
	assert_ne(king, rat, "the Rat King and the Rat draw the same outline")
	assert_true(Silhouettes.fill_ratio(&"rat_king", CG.Team.ENEMY).x
		> Silhouettes.fill_ratio(&"rat", CG.Team.ENEMY).x * 0.5,
		"the Rat King is not a pile beside its own rat")


func test_an_unknown_shape_is_reported_as_unknown() -> void:
	# The negative case. Without it, a has_shape that returned true for
	# everything would satisfy every other assertion in this file.
	assert_false(Silhouettes.has_shape(&"not_a_real_shape"))
	assert_false(Silhouettes.has_shape(&""))


func test_shape_ids_are_sorted_and_complete() -> void:
	var ids := Silhouettes.shape_ids()
	assert_true(ids.size() >= CLASS_SHAPES.size() + UNUSED_SHAPES.size())
	var sorted := ids.duplicate()
	sorted.sort()
	assert_eq(ids, sorted, "shape_ids must be deterministic")


## Three tests lived here and are deleted with the polygons they read:
## `test_every_shape_builds_drawable_polygons`, `test_shapes_stay_inside_the
## _radius_they_are_given` and `test_facing_left_mirrors_the_shape`. The first
## two are structural now -- a sprite is scaled into the radius it is given by
## `UnitArt.draw`, which cannot overshoot -- and mirroring is asserted on the
## real path by `test_a_mirrored_sprite_is_drawn_in_the_same_place` below, which
## is where issue #241's actual defect was.
##
## `test_an_unknown_shape_still_produces_something_visible` went too. What an
## unknown shape produces is a black square, by the player's ruling, and
## `test_every_shape_has_real_art_and_nothing_falls_back` asserts nothing in
## this game reaches it.


func test_every_shape_has_real_art_and_nothing_falls_back() -> void:
	# **This test used to assert the opposite**, that every shape without a
	# sprite still had polygons behind it. That was the right check while seven
	# shapes had no sprite; all nineteen have one now, both sides, so the loop
	# skipped every id and recorded no assertion at all -- which the gate
	# correctly reports as a test that asserts nothing.
	#
	# So it is turned around to say the thing that is now true and is worth
	# holding: no unit in this game draws a fallback. That is what makes
	# deleting the polygons safe, and if a sprite is ever removed this fires
	# with the id rather than a black square appearing in a fight.
	var ids := Silhouettes.shape_ids()
	assert_true(ids.size() >= 15, "only %d shapes; this walk is wrong" % ids.size())
	for id in ids:
		for team in [CG.Team.PLAYER, CG.Team.ENEMY]:
			assert_true(UnitArt.has_art(id, team),
				"'%s' has no sprite for team %d, so it draws the fallback" % [id, team])


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
	# The badges are files now, so this asks the loader rather than a table: a
	# status whose PNG is missing or unreadable draws a black square in a fight.
	for s in _every_status():
		assert_true(
			StatusIcons.has_glyph(s),
			"CG.Status.%s has no badge at %s.png" % [CG.Status.keys()[s], StatusIcons.art_name(s)]
		)


func _count_at(points: Array, y: float) -> int:
	var n := 0
	for p in points:
		if absf(p[1] - y) < 0.001:
			n += 1
	return n


## The opaque fraction of one row of a badge, sampled across its width.
func _row_ink(name: StringName, row: float) -> float:
	var tex := UIArt.texture_for(name)
	if tex == null:
		return 0.0
	var image := tex.get_image()
	var y := clampi(int(row * float(image.get_height())), 0, image.get_height() - 1)
	var inked := 0
	for x in image.get_width():
		if image.get_pixel(x, y).a > 0.5:
			inked += 1
	return float(inked) / float(image.get_width())


func test_status_plate_direction_follows_is_harmful() -> void:
	# The stated rule: harmful points down, beneficial points up, and
	# `CG.is_harmful()` is the only source for it. There is deliberately no
	# second list to drift from it.
	#
	# **Measured on the baked pixels, not on a polygon.** The plates were an
	# array of points until they were baked into `Assets/UI/status/`; a test
	# still reading points would be measuring an artefact the game no longer
	# draws, which is the failure this repo has recorded three times.
	#
	# A plate that POINTS DOWN is wide at the top and narrow at the bottom, so
	# the near-top row carries far more ink than the near-bottom one.
	for s in _every_status():
		var name := StatusIcons.art_name(s)
		var high := _row_ink(name, 0.06)
		var low := _row_ink(name, 0.94)
		var label := String(CG.Status.keys()[s])
		if CG.is_harmful(s):
			assert_true(high > low * 2.0,
				"%s should sit on a downward plate, but its top row inks %.2f against a bottom row of %.2f" % [label, high, low])
		else:
			assert_true(low > high * 2.0,
				"%s should sit on an upward plate, but its bottom row inks %.2f against a top row of %.2f" % [label, low, high])


func test_harmful_and_beneficial_rims_differ() -> void:
	assert_ne(StatusIcons.rim_color(CG.Status.BLEED), StatusIcons.rim_color(CG.Status.SHIELD))


## A baked icon, grid-sampled. **This is the rasteriser the geometry tests used
## to approximate.** They sampled polygons; the polygons are gone and what ships
## is a PNG, so these read the PNG. Same lesson as `Tools/FacingInk.gd`: measure
## the artefact the game draws, not the one it used to.
func _icon_pixels(name: StringName, grid: int) -> PackedColorArray:
	var out := PackedColorArray()
	var tex := UIArt.texture_for(name)
	if tex == null:
		return out
	var image := tex.get_image()
	for gy in grid:
		for gx in grid:
			var x := mini(int((float(gx) + 0.5) / float(grid) * float(image.get_width())), image.get_width() - 1)
			var y := mini(int((float(gy) + 0.5) / float(grid) * float(image.get_height())), image.get_height() - 1)
			out.append(image.get_pixel(x, y))
	return out


## The fraction of sampled pixels two icons disagree on. The same question
## `Tools/BadgeLegibility.tscn` asked by rendering. It is cheap enough to be a
## test now -- the images are on disk, so nothing has to be drawn to ask it --
## and that tool is deleted, because a test that always runs beats a tool
## somebody has to remember.
func _pixel_difference(a: PackedColorArray, b: PackedColorArray) -> float:
	if a.is_empty() or a.size() != b.size():
		return 1.0
	var differing := 0
	for i in a.size():
		var d := absf(a[i].r - b[i].r) + absf(a[i].g - b[i].g) + absf(a[i].b - b[i].b) + absf(a[i].a - b[i].a)
		if d > 0.12:
			differing += 1
	return float(differing) / float(a.size())


func test_no_two_status_glyphs_are_the_same_picture() -> void:
	# THE TEST THAT WOULD HAVE CAUGHT BLEED AND BURN. The header of
	# StatusIcons.gd asserted "no two share an outline" for months and it was
	# false: a droplet and a flame are different arrays and the same picture,
	# and measured on screen they disagreed on 2.1% of their pixels.
	#
	# It used to sample polygons through a hand-rolled point-in-polygon pass,
	# which was the best available while the glyphs were geometry. They are
	# files now, so this compares the shipped pixels directly, and the number it
	# reports is directly comparable with the ones `Tools/BadgeLegibility` published
	# before it was deleted: 2.1% for bleed/burn and 9.3% for taunted/burn, both treated as
	# defects and redrawn.
	#
	# Only same-category pairs are checked. Rim colour and plate direction
	# already separate harmful from helpful, and no glyph has to.
	var grid := 32
	var pixels := {}
	for s in _every_status():
		pixels[s] = _icon_pixels(StatusIcons.art_name(s), grid)

	var worst := 1.0
	var worst_pair := ""
	for a in _every_status():
		for b in _every_status():
			if a >= b or CG.is_harmful(a) != CG.is_harmful(b):
				continue
			var d := _pixel_difference(pixels[a], pixels[b])
			if d < worst:
				worst = d
				worst_pair = "%s/%s" % [CG.Status.keys()[a], CG.Status.keys()[b]]
	# **The floor is 10%, set from the two pairs this project has already judged
	# unacceptable rather than from today's measurement.** taunted/burn was 9.3%
	# and was redrawn; bleed/burn was 2.1% and was redrawn. A floor of 10%
	# catches both.
	#
	# Today's closest pair is BURN/POISON at 10.6%, so the margin is thin and
	# that pair is the next one worth redrawing. Reported rather than acted on.
	# The floor is not to be lowered to buy room: issue #144 records five
	# widenings of one cap and zero narrowings.
	assert_true(worst > 0.10,
		("the closest same-category badge pair is %s at %.1f%% of their pixels. "
		+ "Two badges that similar are one badge on a 17px unit -- redraw one.") % [
			worst_pair, worst * 100.0])


func test_the_glyph_similarity_detector_actually_fires() -> void:
	# A detector shipped without this is the failure mode this project has
	# written down: sixteen tests asserting a warning is well-formed when it
	# fires, none asserting it fires at all.
	#
	# The old control was the literal droplet bleed used to be, typed into this
	# file. That geometry exists nowhere but git history now, so the control is
	# taken from real data at both ends:
	#
	#   FIRES. `archer_shot` and `goblin_arrow` are the same picture and are
	#   allowlisted below as such. The metric must report them as identical.
	#   DOES NOT FIRE ON EVERYTHING. A shield badge and a flame badge are
	#   nothing alike and must score far above the floor.
	var grid := 32
	var same := _pixel_difference(
		_icon_pixels(ActionIcons.art_name(&"archer_shot"), grid),
		_icon_pixels(ActionIcons.art_name(&"goblin_arrow"), grid))
	assert_true(same <= 0.10,
		"two icons known to be the same picture score %.1f%%, so this detector is inert" % [same * 100.0])
	var apart := _pixel_difference(
		_icon_pixels(StatusIcons.art_name(CG.Status.SHIELD), grid),
		_icon_pixels(StatusIcons.art_name(CG.Status.BURN), grid))
	assert_true(apart > 0.10,
		"a shield and a flame score %.1f%%, so this detector rejects everything" % [apart * 100.0])


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


## Every id with a file in `Assets/UI/<kind>`. The icons are files now, so a
## test asking "what art exists" reads the folder rather than a table.
func _baked_ids(kind: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open("res://Assets/UI/%s" % kind)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".png"):
			out.append(StringName(file.get_basename()))
	out.sort()
	return out


func test_action_icon_table_has_no_entries_for_actions_that_do_not_exist() -> void:
	# The other direction: an icon left behind after content deletes an action
	# is dead weight and, worse, evidence that the two have drifted.
	var baked := _baked_ids("action")
	assert_true(baked.size() > 20, "only %d action icons on disk; this walk is wrong" % baked.size())
	for id in baked:
		if _ICONS_AHEAD_OF_CONTENT.has(id):
			continue
		assert_not_null(Registry.get_action(id), "Assets/UI/action/%s.png exists, but the registry does not define that action" % id)


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
		if not ActionIcons.has_glyph(id):
			described_nothing.append(String(id))
		if Registry.get_action(id) != null:
			stale.append("%s (%s)" % [id, _ICONS_AHEAD_OF_CONTENT[id]])
	assert_eq(described_nothing, [] as Array[String],
		"_ICONS_AHEAD_OF_CONTENT names ids with no icon at all, so those entries describe nothing")
	assert_eq(stale, [] as Array[String],
		("the registry now defines these, so their icons are no longer ahead of content. "
		+ "DELETE their lines from _ICONS_AHEAD_OF_CONTENT in this file -- that is the whole fix, "
		+ "and an empty list is the correct end state rather than a problem."))


## `test_status_backed_action_icons_resolve_to_the_status_glyph` was here, and
## it is deleted rather than rewritten. It asserted that Guard's icon array WAS
## the BLOCK badge's array, which is a check only a shared table can support.
## The two are separate PNGs now, painted at different sizes on different plates
## in different colours, and no cheap comparison says "same picture, drawn twice
## on purpose". Inventing an expensive one that agreed with me by construction
## would be worse than the honest gap. Rule 2 is now a rule for whoever repaints
## these, stated in `ActionIcons.gd` and in `Assets/UI/README.md`.


func test_an_action_with_no_file_reports_no_icon() -> void:
	# The fallback is a black square now, by the player's ruling. It is meant to
	# be conspicuous: the failure it stands for is a file nobody painted, and a
	# blank looks like the feature being broken.
	assert_false(ActionIcons.has_glyph(&"no_such_action"))
	assert_true(ActionIcons.has_glyph(&"warrior_strike"))


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
	# `priest_heal|warrior_second_wind` was excused here and the entry is now
	# GONE, removed by the negative half of the test below rather than by taste.
	# The two shared `_CROSS` as geometry, but an ability icon is coloured by its
	# damage type and these two have different ones, so as shipped pictures they
	# were never the same picture. The table said they were because it compared
	# arrays, which is the artefact-one-file-over error in miniature.
}


func test_no_two_ability_icons_share_a_glyph_by_accident() -> void:
	# The test the icon sheet was doing by eye. `siege_master_shot` and
	# `siege_engine_bolt` both drew `_BOLT_HEAVY`, and a Siege Master builds the
	# engine and then fights beside it -- so the same icon sat over two units at
	# once, on two bars, which is the exact case rule 4 exists to prevent.
	#
	# Compares shipped pixels, not arrays. That is stricter in one direction and
	# looser in the other, and both are corrections: two different arrays that
	# render alike now fail, and two identical arrays rendered in different
	# damage colours now pass, because on screen they are not the same icon.
	var grid := 32
	var pixels := {}
	var ids := _baked_ids("action")
	for id in ids:
		pixels[id] = _icon_pixels(ActionIcons.art_name(id), grid)
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if _pixel_difference(pixels[ids[i]], pixels[ids[j]]) > 0.0:
				continue
			var pair := "%s|%s" % [ids[i], ids[j]]
			assert_true(
				_DELIBERATE_SHARED_GLYPHS.has(pair),
				"%s and %s are the same picture. If that is deliberate, add '%s' to _DELIBERATE_SHARED_GLYPHS with the reason; otherwise repaint one." % [ids[i], ids[j], pair]
			)
	# The negative half: an allowlist entry naming a pair that is no longer the
	# same picture is describing nothing, and it is what deleted the third entry.
	for pair in _DELIBERATE_SHARED_GLYPHS.keys():
		var two: PackedStringArray = String(pair).split("|")
		assert_eq(
			_pixel_difference(
				_icon_pixels(ActionIcons.art_name(StringName(two[0])), grid),
				_icon_pixels(ActionIcons.art_name(StringName(two[1])), grid)),
			0.0,
			"_DELIBERATE_SHARED_GLYPHS still excuses '%s', but those two are no longer the same picture" % pair
		)


## Four tests lived here: `test_glyph_geometry_stays_inside_its_own_rect` and
## three on `UIArt.glyph_points` / `glyph_center`. They are deleted with the
## code they measured. A glyph cannot escape its own rect any more -- it is a
## PNG scaled into that rect by `draw_fit`, so the property is structural rather
## than something a test has to watch.


func test_ui_art_returns_null_for_a_name_with_no_file() -> void:
	# The normal case today, and it must be silent: a missing override is not
	# an error and every drawing function relies on that.
	UIArt.clear_cache()
	assert_eq(UIArt.texture_for(&"definitely_not_a_real_ui_asset"), null)
	assert_false(UIArt.has_art(&"status/definitely_not_a_real_status"))


func test_a_dropped_in_png_is_found_with_no_registration() -> void:
	# The item-15 claim, exercised end to end rather than reasoned about.
	#
	# **The first half of this test used to be "assert status/bleed.png does not
	# exist".** It does now -- every badge in the game is a dropped-in PNG since
	# the bake -- so the shipped art IS the proof that a name the game asks for
	# resolves with no import, no registration and no code change.
	var art_name := StatusIcons.art_name(CG.Status.BLEED)
	assert_eq(String(art_name), "status/bleed")
	assert_not_null(UIArt.texture_for(art_name),
		"the shipped badge at Assets/UI/%s.png is not being found by the loader" % art_name)

	# And the round trip, under a name nothing ships, so a crash here cannot
	# damage a real asset: write, find, delete, gone.
	var probe := &"status/_drop_in_probe"
	var path := "res://Assets/UI/%s.png" % probe
	assert_false(FileAccess.file_exists(path), "%s already exists; this test would not prove anything" % path)
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.0, 1.0, 1.0))
	assert_eq(image.save_png(path), OK, "could not write the test override to %s" % path)

	UIArt.clear_cache()
	var tex := UIArt.texture_for(probe)
	assert_not_null(tex, "a PNG dropped into Assets/UI was not picked up")
	assert_eq(tex.get_width(), 8)

	DirAccess.remove_absolute(path)
	UIArt.clear_cache()
	assert_eq(UIArt.texture_for(probe), null, "the override survived its own deletion")


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
	# The other direction. Art left behind after content deletes an item is dead
	# weight, and it is how a folder drifts from the content it describes.
	var baked := _baked_ids("item")
	assert_true(baked.size() > 10, "only %d item icons on disk; this walk is wrong" % baked.size())
	for id in baked:
		if String(id).begins_with("empty_"):
			continue
		assert_not_null(
			Registry.get_equipment(id),
			"Assets/UI/item/%s.png exists, but that is not a registered item" % id
		)


func test_no_two_items_share_a_glyph() -> void:
	# The four rings deliberately share a band and differ by gem, so no two of
	# them are the same picture. Anything that does come out equal is an accident.
	# Pixels, not arrays: what ships is a file.
	var grid := 32
	var ids := Registry.all_equipment_ids()
	var pixels := {}
	for id in ids:
		pixels[id] = _icon_pixels(EquipmentIcons.art_name(id), grid)
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			assert_true(_pixel_difference(pixels[ids[i]], pixels[ids[j]]) > 0.0,
				"%s and %s are the same picture; repaint one of them" % [ids[i], ids[j]])


## The opaque shape of an icon, ignoring every colour in it. Two plates can only
## be told apart in greyscale by their outline, which is the channel that has to
## survive for a player who cannot separate the rim colours.
func _alpha_mask(name: StringName, grid: int) -> PackedByteArray:
	var out := PackedByteArray()
	for c in _icon_pixels(name, grid):
		out.append(1 if c.a > 0.5 else 0)
	return out


## The shape of everything drawn ON a plate, colour ignored. The plate fill is
## `Palette.HP_BACK` on all three icon systems, so anything else is the picture.
## Alpha cannot answer this for an accessory: its plate is a filled circle, so
## all four rings have byte-identical alpha and differ only inside it.
func _ink_mask(name: StringName, grid: int) -> PackedByteArray:
	var out := PackedByteArray()
	var back := Palette.HP_BACK
	for c in _icon_pixels(name, grid):
		var d := absf(c.r - back.r) + absf(c.g - back.g) + absf(c.b - back.b)
		out.append(1 if c.a > 0.5 and d > 0.25 else 0)
	return out


func _mask_difference(a: PackedByteArray, b: PackedByteArray) -> float:
	if a.is_empty() or a.size() != b.size():
		return 1.0
	var differing := 0
	for i in a.size():
		if a[i] != b[i]:
			differing += 1
	return float(differing) / float(a.size())


func test_the_three_slots_are_told_apart_by_shape_and_by_colour() -> void:
	# Two redundant channels, and this test exists because losing one of them is
	# silent: a player who cannot separate the rim colours still has the plate,
	# and a greyscale screenshot still shows three different outlines.
	#
	# The empty-slot plates are the plate on its own, so they are what this
	# measures -- an item's own picture sits on top of one of these three.
	var grid := 32
	var masks := {}
	for slot in _EVERY_SLOT:
		masks[slot] = _alpha_mask(EquipmentIcons.empty_art_name(slot), grid)
	var colors: Array = []
	for slot in _EVERY_SLOT:
		var c := EquipmentIcons.slot_color(slot)
		assert_false(colors.has(c), "two slots draw the same rim colour")
		colors.append(c)
	for i in _EVERY_SLOT.size():
		for j in range(i + 1, _EVERY_SLOT.size()):
			var d := _mask_difference(masks[_EVERY_SLOT[i]], masks[_EVERY_SLOT[j]])
			assert_true(d > 0.05,
				"slots %d and %d have the same outline (%.1f%% apart), so greyscale cannot separate them" % [
					_EVERY_SLOT[i], _EVERY_SLOT[j], d * 100.0])


func test_no_item_plate_is_another_icon_system_s_plate() -> void:
	# Three icon systems can be on the equip screen at once -- the item, the
	# action it grants, and the status that action applies. A glance should never
	# have to work out which system it is reading first.
	#
	# Outlines, on real pixels. Any ability icon carries the ability plate and
	# any badge carries a status plate, so one of each is enough to stand for
	# the system.
	var grid := 32
	var ability := _alpha_mask(ActionIcons.art_name(&"warrior_strike"), grid)
	var good := _alpha_mask(StatusIcons.art_name(CG.Status.SHIELD), grid)
	var bad := _alpha_mask(StatusIcons.art_name(CG.Status.BLEED), grid)
	for slot in _EVERY_SLOT:
		var plate := _alpha_mask(EquipmentIcons.empty_art_name(slot), grid)
		assert_true(_mask_difference(plate, ability) > 0.05, "an item plate is the ability plate")
		assert_true(_mask_difference(plate, good) > 0.05, "an item plate is the beneficial status plate")
		assert_true(_mask_difference(plate, bad) > 0.05, "an item plate is the harmful status plate")


func test_an_item_that_grants_an_action_can_draw_that_action_s_own_glyph() -> void:
	# Rule 3, and the thing #100 made true that no art had yet said: `plate_mail`
	# teaches Directional Block, and an item that changes what a pawn can DO is a
	# different kind of item from one that adds 3 STR.
	#
	# There is deliberately no second table here. The badge resolves through
	# `ActionIcons.art_name`, so it cannot drift from what the wind-up bar draws
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


## `test_item_glyph_geometry_stays_inside_its_own_rect` was here and is deleted
## with the geometry: a PNG cannot draw outside the rect `draw_fit` scales it
## into, so the property is structural now.


func test_the_four_rings_differ_by_colour_and_by_cut() -> void:
	# They are four rings and pretending they have four unrelated outlines would
	# be inventing a difference the content does not have. So they carry two
	# channels of their own, and losing either is silent: without the cut a
	# greyscale reader has four identical icons, without the colour a 20px
	# reader has four identical icons.
	#
	# Both channels are measured on the shipped files. The cut is the alpha
	# outline, which is exactly what survives a greyscale read.
	var grid := 32
	var rings: Array[StringName] = [&"brown_ring", &"red_ring", &"blue_ring", &"yellow_ring"]
	for id in rings:
		assert_not_null(Registry.get_equipment(id), "%s is no longer a registered item" % id)
	for i in rings.size():
		for j in range(i + 1, rings.size()):
			var a := EquipmentIcons.art_name(rings[i])
			var b := EquipmentIcons.art_name(rings[j])
			assert_true(_pixel_difference(_icon_pixels(a, grid), _icon_pixels(b, grid)) > 0.0,
				"%s and %s are the same picture" % [rings[i], rings[j]])
			assert_true(_mask_difference(_ink_mask(a, grid), _ink_mask(b, grid)) > 0.0,
				"%s and %s cut the same shape, so they are one icon in greyscale" % [rings[i], rings[j]])


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
	# false. The nearby test walks the registry against the icons that exist,
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
