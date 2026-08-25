extends SceneTree

## Issue 566. Writes the part sprites `Assets/Units/parts/` holds.
##
## Run once, commit the output. Nothing in the game ever calls this: a part is a
## PNG on disk, and a missing one is a black square per the player's ruling.
## It ships beside the assets so the constants below can be changed and the set
## regenerated, which is the whole point of a recipe over a drawing.

const OUT_DIR := "res://Assets/Units/parts"

## Every part is drawn on this one square canvas, already in its place. So
## composing a unit is overlaying parts in one rect, and a Rotund body and a
## Skinny body differ by which pixels they fill rather than by a fit rule.
##
## The player, 2026-08-24, on the 32 this used to be: "Even for the full game
## that seems a little conservative". Units draw at 20-60 px on screen, so 256
## is 4x to 12x supersampled -- it downsamples clean and leaves room for a zoom
## or a resolution this game does not ship at yet. A 32 px source scaled UP is
## the failure that cannot be undone later.
const N := 256

## Parts are AUTHORED in a 32-unit square and rasterised at `N`. So the
## coordinates below read as proportions of a body and changing `N` needs no
## edit to any of them.
const DESIGN := 32.0

## The capsule's half-width, in design units. Every other body's width is stated
## against it because the taper floor below is a ratio, not a number of pixels.
const CAPSULE_HALF_WIDTH := 5.0

## The player's floor on the inverted triangle: "they should never get more
## narrow than half the capsule body sizes."
const MIN_TAPER := 0.5

static func _scale() -> float:
	return float(N) / DESIGN

## One pixel's centre, in design units.
static func _at(x: int, y: int) -> Vector2:
	var s := _scale()
	return Vector2((float(x) + 0.5) / s, (float(y) + 0.5) / s)

## White with an alpha channel. The colour is the recipe's, applied when the
## layers are composed, so one `body_skinny` serves a green goblin and a pink
## human.
static func _blank() -> Image:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	return img

static func _ink(img: Image, x: int, y: int) -> void:
	if x >= 0 and y >= 0 and x < N and y < N:
		img.set_pixel(x, y, Color.WHITE)

## An axis-aligned ellipse, filled. Every body and head below is one or two of
## these, which is what keeps the set small enough to be a recipe.
static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float) -> void:
	for y in N:
		for x in N:
			var p := _at(x, y)
			var dx := (p.x - cx) / rx
			var dy := (p.y - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_ink(img, x, y)

static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in N:
		for x in N:
			var p := _at(x, y)
			if p.x >= float(x0) and p.x < float(x1) and p.y >= float(y0) and p.y < float(y1):
				_ink(img, x, y)

## A thick segment, for a limb. The arms were straight horizontal stubs in the
## first bake and read as a T-pose; an arm needs an angle and a rectangle cannot
## have one.
static func _limb(img: Image, a: Vector2, b: Vector2, half: float) -> void:
	for y in N:
		for x in N:
			var p := _at(x, y)
			var ab := b - a
			var t := 0.0 if ab.length_squared() <= 0.0 else 				clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			if p.distance_to(a + ab * t) <= half:
				_ink(img, x, y)

## A filled triangle, by half-plane test. The player's own words for the
## features: "pretty much just polygons, think small triangles for a goblin's
## nose and ears".
static func _tri(img: Image, a: Vector2, b: Vector2, c: Vector2) -> void:
	for y in N:
		for x in N:
			var p := _at(x, y)
			var d1 := _side(p, a, b)
			var d2 := _side(p, b, c)
			var d3 := _side(p, c, a)
			var neg: bool = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
			var pos: bool = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
			if not (neg and pos):
				_ink(img, x, y)

static func _side(p: Vector2, a: Vector2, b: Vector2) -> float:
	return (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)

## The parts, and the whole vocabulary is here. A new creature is a line in
## `UnitRecipes`, not a drawing.
func _parts() -> Dictionary:
	var out := {}

	# --- the player's three body types -------------------------------------
	# Skinny, a capsule. CAPSULE_HALF_WIDTH is the reference every other body is
	# measured against, because the player set the taper floor as a ratio to it.
	var skinny := _blank()
	_ellipse(skinny, 16.0, 14.0, CAPSULE_HALF_WIDTH, CAPSULE_HALF_WIDTH)
	_rect(skinny, int(16.0 - CAPSULE_HALF_WIDTH), 14, int(16.0 + CAPSULE_HALF_WIDTH), 28)
	_ellipse(skinny, 16.0, 28.0, CAPSULE_HALF_WIDTH, CAPSULE_HALF_WIDTH)
	out["body_skinny"] = skinny

	# Muscular, an inverted triangle. The player: "For the inverted triangle
	# bodies they should never get more narrow than half the capsule body sizes."
	# So it is a trapezoid rather than a triangle -- a true triangle ends in a
	# point, which is narrower than any floor.
	var muscular := _blank()
	var hip := CAPSULE_HALF_WIDTH * MIN_TAPER
	_tri(muscular, Vector2(4.0, 12.0), Vector2(28.0, 12.0), Vector2(16.0 - hip, 30.0))
	_tri(muscular, Vector2(28.0, 12.0), Vector2(16.0 + hip, 30.0), Vector2(16.0 - hip, 30.0))
	_ellipse(muscular, 16.0, 13.0, 12.0, 3.5)
	out["body_muscular"] = muscular

	# Rotund, a circle.
	var rotund := _blank()
	_ellipse(rotund, 16.0, 21.5, 11.0, 10.5)
	out["body_rotund"] = rotund

	# A fourth that is not one of the three, for the things that are not people.
	# Long and low: the rat's own identity, which `test_art.gd` asserts.
	var low := _blank()
	_ellipse(low, 16.0, 24.0, 13.0, 6.0)
	out["body_low"] = low

	# --- heads --------------------------------------------------------------
	var head := _blank()
	_ellipse(head, 16.0, 7.5, 5.5, 5.5)
	out["head_round"] = head

	var tall := _blank()
	_ellipse(tall, 16.0, 8.0, 4.0, 6.0)
	out["head_tall"] = tall

	var small := _blank()
	_ellipse(small, 16.0, 8.5, 4.2, 4.2)
	out["head_small"] = small

	# A head that sits forward on a low body rather than on top of a tall one.
	# Sunk so its top sits level with the low body's, not above it. On the Rat
	# King the back is three crests by assertion, and a head poking over the
	# spine's valley floor scored a fourth.
	var snout := _blank()
	_ellipse(snout, 25.0, 23.0, 4.5, 4.0)
	_tri(snout, Vector2(28.0, 21.0), Vector2(32.0, 24.0), Vector2(28.0, 26.0))
	out["head_snouted"] = snout

	# --- features, the distinguishing half ----------------------------------
	# The goblin's ears, and they are the player's worked example.
	var ears := _blank()
	_tri(ears, Vector2(12.0, 5.4), Vector2(6.6, 2.8), Vector2(12.0, 9.8))
	_tri(ears, Vector2(20.0, 5.4), Vector2(25.4, 2.8), Vector2(20.0, 9.8))
	out["ears_pointed"] = ears


	# The nose, a small triangle, pointing the way the unit faces.
	var nose := _blank()
	_tri(nose, Vector2(16.0, 7.0), Vector2(22.0, 10.0), Vector2(16.0, 12.0))
	out["nose_triangle"] = nose

	var horns := _blank()
	_tri(horns, Vector2(11.0, 6.0), Vector2(8.0, 0.0), Vector2(14.0, 4.0))
	_tri(horns, Vector2(21.0, 6.0), Vector2(24.0, 0.0), Vector2(18.0, 4.0))
	out["horns"] = horns

	var crown := _blank()
	_tri(crown, Vector2(10.0, 5.0), Vector2(13.0, 0.0), Vector2(16.0, 5.0))
	_tri(crown, Vector2(13.0, 5.0), Vector2(16.0, 0.0), Vector2(19.0, 5.0))
	_tri(crown, Vector2(16.0, 5.0), Vector2(19.0, 0.0), Vector2(22.0, 5.0))
	out["crown"] = crown

	var hood := _blank()
	_tri(hood, Vector2(16.0, 0.0), Vector2(8.0, 13.0), Vector2(24.0, 13.0))
	out["hood"] = hood

	var plume := _blank()
	_tri(plume, Vector2(16.0, 5.0), Vector2(13.0, 0.0), Vector2(19.0, 0.0))
	out["plume"] = plume

	# Eyes. Two pixels is all it takes at this size and it is what turns a
	# silhouette into a creature facing you.
	var eyes := _blank()
	_rect(eyes, 13, 7, 15, 9)
	_rect(eyes, 17, 7, 19, 9)
	out["eyes"] = eyes

	var eyes_low := _blank()
	_rect(eyes_low, 24, 21, 26, 23)
	out["eyes_snout"] = eyes_low

	var tusks := _blank()
	_tri(tusks, Vector2(12.0, 11.0), Vector2(11.0, 15.0), Vector2(14.0, 11.0))
	_tri(tusks, Vector2(20.0, 11.0), Vector2(21.0, 15.0), Vector2(18.0, 11.0))
	out["tusks"] = tusks

	# It sweeps low rather than up. Raised, its tip is a local maximum before the
	# back even starts, and on the Rat King that scored as a fourth crest -- which
	# I guessed at four times and only found by printing the top profile.
	var tail := _blank()
	_tri(tail, Vector2(5.0, 22.5), Vector2(-1.0, 21.0), Vector2(5.0, 27.5))
	out["tail"] = tail

	# Three of them, and the count is load-bearing: `test_art.gd` asserts the Rat
	# King's back is three crests and not a dome, because one dome is one animal.
	# Deep valleys between them on purpose -- the detector measures the valley,
	# not the peak.
	var spikes := _blank()
	for i in 3:
		var x := 9.0 + float(i) * 6.0
		_tri(spikes, Vector2(x - 3.2, 16.0), Vector2(x, 5.0), Vector2(x + 3.2, 16.0))
	out["spikes"] = spikes

	# A hat, which is the whole thesis of this issue in one part: the player asked
	# for the archer to be "the goblin base with a hat on basically", so a variant
	# costs a part rather than a drawing.
	var hat := _blank()
	_rect(hat, 9, 5, 23, 6)
	_tri(hat, Vector2(16.0, 0.0), Vector2(11.0, 5.0), Vector2(21.0, 5.0))
	out["hat"] = hat

	var helm := _blank()
	_ellipse(helm, 16.0, 7.0, 6.0, 5.0)
	_rect(helm, 10, 7, 22, 9)
	out["helm"] = helm

	var mandibles := _blank()
	_tri(mandibles, Vector2(13.0, 12.0), Vector2(10.0, 17.0), Vector2(15.0, 13.0))
	_tri(mandibles, Vector2(19.0, 12.0), Vector2(22.0, 17.0), Vector2(17.0, 13.0))
	out["mandibles"] = mandibles

	var wheels := _blank()
	_ellipse(wheels, 9.0, 27.0, 4.5, 4.5)
	_ellipse(wheels, 23.0, 27.0, 4.5, 4.5)
	out["wheels"] = wheels

	var barrel := _blank()
	_rect(barrel, 14, 4, 19, 16)
	_ellipse(barrel, 16.5, 4.0, 3.5, 3.0)
	out["barrel"] = barrel

	# --- hands, plain circles, the player's word --------------------------
	# The player: "ditch arms and let the hands float around." So there is no
	# limb, and the T-pose the arms produced cannot come back by being angled
	# differently -- there is nothing left to angle.
	var hands := _blank()
	_ellipse(hands, 7.5, 21.0, 3.0, 3.0)
	_ellipse(hands, 24.5, 21.0, 3.0, 3.0)
	out["hands"] = hands

	var hands_wide := _blank()
	_ellipse(hands_wide, 4.0, 19.0, 3.8, 3.8)
	_ellipse(hands_wide, 28.0, 19.0, 3.8, 3.8)
	out["hands_wide"] = hands_wide


	return out

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var parts := _parts()
	var names := parts.keys()
	names.sort()
	for name in names:
		var img: Image = parts[name]
		var used := img.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			printerr("BakeParts: '%s' puts no ink on the canvas" % name)
			continue
		img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("BakeParts: %d part(s) at %dx%d written to %s" % [names.size(), N, N, OUT_DIR])
	_bake_units()
	quit(0)

## Every recipe, composed and written as `<id>.<side>.png`. `UnitArt.texture_for`
## looks for a side-specific file BEFORE a shared one, so a composed unit beats
## the older single drawing without a line of lookup code.
##
## Baked rather than composed at run time because at 256 the composition is
## hundreds of thousands of per-pixel operations, and a fresh unit appearing
## mid-fight must not stall the frame it appears on.
func _bake_units() -> void:
	UnitRecipes.clear_cache()
	var total := 0
	for id in UnitRecipes.recipe_ids():
		for team in [CG.Team.PLAYER, CG.Team.ENEMY]:
			var img := UnitRecipes.compose_image(id, team)
			if img == null:
				printerr("BakeParts: recipe '%s' composed nothing" % id)
				continue
			img.save_png(UnitArt.path_for(id, team))
			total += 1
		var used := UnitRecipes.compose_image(id, CG.Team.PLAYER).get_used_rect()
		print("  %-16s ink %3d x %3d of %d" % [id, used.size.x, used.size.y, N])
	print("BakeParts: %d composed unit file(s) written to %s" % [total, UnitArt.ART_DIR])
