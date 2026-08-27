extends SceneTree

## Issue 671: the three Sellsword ability icons, baked once to 128x128 PNGs the
## way every other action icon ships. `ActionIcons.has_glyph` is a file check,
## so an action without a file draws a black square and fails `test_art`.
##
##   godot --headless --path . --script res://Tools/BakeSellswordIcons.gd

const SIZE := 128
const OUT := "res://Assets/UI/action"

## Elite, not boss: one flat ink colour on transparency, the same read as the
## goblin and warden icons rather than anything brighter.
const INK := Color(0.90, 0.91, 0.95, 1.0)
const DIM := Color(0.55, 0.60, 0.72, 1.0)

func _initialize() -> void:
	_save(_seeker_bolts(), "sellsword_seeker_bolts")
	_save(_strike(), "sellsword_strike")
	_save(_crescent(), "sellsword_crescent")
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

func _line(img: Image, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var steps := int(a.distance_to(b) * 2.0) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		_dot(img, p, width, c)

func _dot(img: Image, at: Vector2, r: float, c: Color) -> void:
	var x0 := maxi(0, int(at.x - r)); var x1 := mini(SIZE - 1, int(at.x + r))
	var y0 := maxi(0, int(at.y - r)); var y1 := mini(SIZE - 1, int(at.y + r))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x, y).distance_to(at) <= r:
				img.set_pixel(x, y, c)

## Two darts, so "two bolts" reads from the icon and not only from the tooltip.
func _seeker_bolts() -> Image:
	var img := _blank()
	for off in [-22.0, 22.0]:
		var tail := Vector2(20, 74 + off * 0.35)
		var head := Vector2(100, 54 + off)
		_line(img, tail, head, 4.0, INK)
		_line(img, head, head + Vector2(-18, -8), 4.0, INK)
		_line(img, head, head + Vector2(-18, 8), 4.0, INK)
		_line(img, tail, tail + Vector2(-10, -6), 3.0, DIM)
	return img

## A straight blade. Deliberately the plainest of the three.
func _strike() -> Image:
	var img := _blank()
	_line(img, Vector2(28, 100), Vector2(100, 28), 7.0, INK)
	_line(img, Vector2(24, 104), Vector2(40, 88), 9.0, DIM)
	_line(img, Vector2(30, 78), Vector2(50, 98), 5.0, DIM)
	return img

## An arc, drawn as an arc, because the action is an arc. Same rule the shader
## follows: the icon should not claim a shape the hitbox does not have.
func _crescent() -> Image:
	var img := _blank()
	var centre := Vector2(30, 64)
	for band in [52.0, 46.0]:
		var thick := 6.0 if band == 52.0 else 3.0
		var col := INK if band == 52.0 else DIM
		var steps := 48
		for i in steps + 1:
			var a := lerpf(-0.85, 0.85, float(i) / float(steps))
			_dot(img, centre + Vector2(cos(a), sin(a)) * band, thick, col)
	return img
