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
const N := 32

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
			var dx := (float(x) + 0.5 - cx) / rx
			var dy := (float(y) + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_ink(img, x, y)

static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			_ink(img, x, y)

## A thick segment, for a limb. The arms were straight horizontal stubs in the
## first bake and read as a T-pose; an arm needs an angle and a rectangle cannot
## have one.
static func _limb(img: Image, a: Vector2, b: Vector2, half: float) -> void:
	for y in N:
		for x in N:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
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
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
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
	# Skinny, a capsule.
	var skinny := _blank()
	_ellipse(skinny, 16.0, 15.0, 4.0, 4.0)
	_rect(skinny, 12, 15, 20, 27)
	_ellipse(skinny, 16.0, 27.0, 4.0, 4.0)
	out["body_skinny"] = skinny

	# Muscular, an inverted triangle: wide at the shoulders, narrow at the hips.
	var muscular := _blank()
	_tri(muscular, Vector2(5.0, 12.0), Vector2(27.0, 12.0), Vector2(16.0, 31.0))
	_ellipse(muscular, 16.0, 13.0, 11.0, 3.0)
	out["body_muscular"] = muscular

	# Rotund, a circle.
	var rotund := _blank()
	_ellipse(rotund, 16.0, 22.0, 10.0, 9.5)
	out["body_rotund"] = rotund

	# A fourth that is not one of the three, for the things that are not people.
	# Long and low: the rat's own identity, which `test_art.gd` asserts.
	var low := _blank()
	_ellipse(low, 16.0, 24.0, 13.0, 6.0)
	out["body_low"] = low

	# --- heads --------------------------------------------------------------
	var head := _blank()
	_ellipse(head, 16.0, 8.0, 5.0, 5.0)
	out["head_round"] = head

	var tall := _blank()
	_ellipse(tall, 16.0, 8.0, 4.0, 6.0)
	out["head_tall"] = tall

	var small := _blank()
	_ellipse(small, 16.0, 9.0, 3.5, 3.5)
	out["head_small"] = small

	# A head that sits forward on a low body rather than on top of a tall one.
	var snout := _blank()
	_ellipse(snout, 25.0, 20.0, 4.5, 4.0)
	_tri(snout, Vector2(28.0, 18.0), Vector2(32.0, 21.0), Vector2(28.0, 23.0))
	out["head_snouted"] = snout

	# --- features, the distinguishing half ----------------------------------
	# The goblin's ears, and they are the player's worked example.
	var ears := _blank()
	_tri(ears, Vector2(12.0, 6.0), Vector2(7.0, 4.0), Vector2(12.0, 10.0))
	_tri(ears, Vector2(20.0, 6.0), Vector2(25.0, 4.0), Vector2(20.0, 10.0))
	out["ears_pointed"] = ears

	var ears_round := _blank()
	_ellipse(ears_round, 10.5, 5.0, 2.5, 2.5)
	_ellipse(ears_round, 21.5, 5.0, 2.5, 2.5)
	out["ears_round"] = ears_round

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
	_rect(eyes_low, 24, 18, 26, 20)
	out["eyes_snout"] = eyes_low

	var tusks := _blank()
	_tri(tusks, Vector2(12.0, 11.0), Vector2(11.0, 15.0), Vector2(14.0, 11.0))
	_tri(tusks, Vector2(20.0, 11.0), Vector2(21.0, 15.0), Vector2(18.0, 11.0))
	out["tusks"] = tusks

	var tail := _blank()
	_tri(tail, Vector2(4.0, 22.0), Vector2(-2.0, 14.0), Vector2(5.0, 26.0))
	out["tail"] = tail

	var spikes := _blank()
	for i in 3:
		var x := 9.0 + float(i) * 6.0
		_tri(spikes, Vector2(x - 3.0, 15.0), Vector2(x, 8.0), Vector2(x + 3.0, 15.0))
	out["spikes"] = spikes

	# --- hands, plain circles, the player's word --------------------------
	# The circle is the player's word for the HAND. The arm it hangs on is not
	# decoration: straight horizontal stubs read as a T-pose, which is a posture
	# nobody asked for.
	var hands := _blank()
	_limb(hands, Vector2(12.5, 16.0), Vector2(8.5, 25.0), 1.6)
	_limb(hands, Vector2(19.5, 16.0), Vector2(23.5, 25.0), 1.6)
	_ellipse(hands, 8.0, 26.0, 2.5, 2.5)
	_ellipse(hands, 24.0, 26.0, 2.5, 2.5)
	out["hands"] = hands

	var hands_wide := _blank()
	_limb(hands_wide, Vector2(10.0, 14.0), Vector2(5.0, 23.0), 2.2)
	_limb(hands_wide, Vector2(22.0, 14.0), Vector2(27.0, 23.0), 2.2)
	_ellipse(hands_wide, 4.5, 24.5, 3.0, 3.0)
	_ellipse(hands_wide, 27.5, 24.5, 3.0, 3.0)
	out["hands_wide"] = hands_wide

	# Feet, for the same reason hands are: a body with nothing under it floats.
	var feet := _blank()
	_ellipse(feet, 12.5, 30.0, 3.0, 2.0)
	_ellipse(feet, 19.5, 30.0, 3.0, 2.0)
	out["feet"] = feet

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
		print("  %-16s %2d x %2d ink at %s" % [name, used.size.x, used.size.y, used.position])
	print("BakeParts: %d part(s) written to %s" % [names.size(), OUT_DIR])
	quit(0)
