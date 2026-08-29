extends SceneTree

## Issue 746: the shield, focus and quiver item icons, baked once to 128x128
## PNGs the way `Tools/BakeSellswordIcons.gd` baked its three. `EquipmentIcons.
## has_glyph` is a file check, so an item without one draws a black square and
## fails `test_art`.
##
##   godot --headless --path . --script res://Tools/BakeOffHandIcons.gd

const SIZE := 128
const OUT := "res://Assets/UI/item"

const INK := Color(0.90, 0.91, 0.95, 1.0)
const DIM := Color(0.55, 0.60, 0.72, 1.0)

func _initialize() -> void:
	_save(_shield(), "shield")
	_save(_focus(), "focus")
	_save(_quiver(), "quiver")
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

func _ring(img: Image, centre: Vector2, r: float, width: float, c: Color, a0: float = 0.0, a1: float = TAU) -> void:
	var steps := 64
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / float(steps))
		_dot(img, centre + Vector2(cos(a), sin(a)) * r, width, c)

## A kite outline with a spine down the middle -- the shape the equip screen's
## own doc comment (`EquipmentDef.gd`) uses as the shield example.
func _shield() -> Image:
	var img := _blank()
	var top := Vector2(64, 22)
	var l := Vector2(28, 44)
	var r := Vector2(100, 44)
	var tip := Vector2(64, 108)
	_line(img, top, l, 6.0, INK)
	_line(img, top, r, 6.0, INK)
	_line(img, l, tip, 6.0, INK)
	_line(img, r, tip, 6.0, INK)
	_line(img, top, tip, 4.0, DIM)
	return img

## A ringed lens: a focus is read at a glance, so a caster's talisman gets a
## simple concentric shape rather than anything narrative.
func _focus() -> Image:
	var img := _blank()
	var centre := Vector2(64, 64)
	_ring(img, centre, 38.0, 6.0, INK)
	_ring(img, centre, 20.0, 4.0, DIM)
	_dot(img, centre, 6.0, INK)
	return img

## Three fletched shafts angled into one bundle, the quiver's contents rather
## than the case that holds them -- the arrowheads are what a bleed chance is.
func _quiver() -> Image:
	var img := _blank()
	for off in [-24.0, 0.0, 24.0]:
		var tail := Vector2(50 + off * 0.3, 106)
		var head := Vector2(70 + off, 22)
		_line(img, tail, head, 4.0, INK if off == 0.0 else DIM)
		_line(img, head, head + Vector2(-8, 14), 3.0, INK if off == 0.0 else DIM)
		_line(img, head, head + Vector2(8, 14), 3.0, INK if off == 0.0 else DIM)
	return img
