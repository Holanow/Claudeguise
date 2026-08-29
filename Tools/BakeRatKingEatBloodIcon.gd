extends SceneTree

## Issue 759: the Rat King's eating action icon, baked once to a 128x128 PNG
## the way every other action icon ships. `ActionIcons.has_glyph` is a file
## check, so an action without a file draws a black square and fails
## `test_art`.
##
##   godot --headless --path . --script res://Tools/BakeRatKingEatBloodIcon.gd

const SIZE := 128
const OUT := "res://Assets/UI/action"

const BLOOD := Color(0.72, 0.10, 0.16, 1.0)
const BLOOD_DIM := Color(0.42, 0.06, 0.10, 1.0)

func _initialize() -> void:
	_save(_droplet(), "rat_king_eat_blood")
	quit(0)

func _blank() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

func _save(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	print("wrote %s" % path)

func _dot(img: Image, at: Vector2, r: float, c: Color) -> void:
	var x0 := maxi(0, int(at.x - r)); var x1 := mini(SIZE - 1, int(at.x + r))
	var y0 := maxi(0, int(at.y - r)); var y1 := mini(SIZE - 1, int(at.y + r))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x, y).distance_to(at) <= r:
				img.set_pixel(x, y, c)

## A pool being drawn up into a droplet: a wide flat puddle beneath, a teardrop
## rising out of it -- "eating the ground" read as one shape.
func _droplet() -> Image:
	var img := _blank()
	var puddle := Vector2(64, 96)
	for x in range(-30, 31):
		var y := 96.0 - sqrt(maxf(0.0, 1.0 - pow(float(x) / 32.0, 2.0))) * 10.0
		_dot(img, puddle + Vector2(x, y - 96.0), 9.0, BLOOD_DIM)
	var tip := Vector2(64, 22)
	var base := Vector2(64, 78)
	var steps := 40
	for i in steps + 1:
		var t := float(i) / float(steps)
		var width := lerpf(2.0, 20.0, t)
		var centre := tip.lerp(base, t)
		_dot(img, centre, width * 0.5, BLOOD)
	return img
