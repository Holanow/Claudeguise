extends SceneTree

## Issue 918: every icon the README's floor 1 base types need, plus the five
## empty slot plates #886 found missing, plus the Rallying Cry the Standard
## grants. `has_glyph` is a file check, so a piece without one draws a black
## square and fails `test_art`.
##
##   godot --headless --path . --script res://Tools/BakeEquipment918.gd

const SIZE := 128
const ITEM_OUT := "res://Assets/UI/item"
const ACTION_OUT := "res://Assets/UI/action"

const INK := Color(0.90, 0.91, 0.95, 1.0)
const DIM := Color(0.55, 0.60, 0.72, 1.0)
const WARM := Color(0.88, 0.70, 0.38, 1.0)

## The plate fill every icon system shares, so a slot plate reads as a plate.
const PLATE := Color(0.165, 0.153, 0.200, 1.0)

func _initialize() -> void:
	_save(ITEM_OUT, _mace(), "mace")
	_save(ITEM_OUT, _rune_gauntlet(), "rune_gauntlet")
	_save(ITEM_OUT, _reaper(), "reaper")
	_save(ITEM_OUT, _wand(), "wand")
	_save(ITEM_OUT, _tower_shield(), "tower_shield")
	_save(ITEM_OUT, _standard(), "standard")
	_save(ITEM_OUT, _book(), "book")
	_save(ITEM_OUT, _great_helm(), "great_helm")
	_save(ITEM_OUT, _hood(), "hood")
	_save(ITEM_OUT, _plate_diamond(), "empty_main_hand")
	_save(ITEM_OUT, _plate_disc(), "empty_off_hand")
	_save(ITEM_OUT, _plate_arch(), "empty_head")
	_save(ITEM_OUT, _plate_octagon(), "empty_body")
	_save(ITEM_OUT, _plate_ring(), "empty_accessory")
	_save(ACTION_OUT, _rallying_cry(), "rallying_cry")
	quit(0)

func _blank() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

func _save(dir_path: String, img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var path := "%s/%s.png" % [dir_path, name]
	img.save_png(path)
	print("wrote %s" % path)

func _dot(img: Image, at: Vector2, r: float, c: Color) -> void:
	var x0 := maxi(0, int(at.x - r))
	var x1 := mini(SIZE - 1, int(at.x + r))
	var y0 := maxi(0, int(at.y - r))
	var y1 := mini(SIZE - 1, int(at.y + r))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x, y).distance_to(at) <= r:
				img.set_pixel(x, y, c)

func _line(img: Image, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var steps := int(a.distance_to(b) * 2.0) + 1
	for i in steps + 1:
		_dot(img, a.lerp(b, float(i) / float(steps)), width, c)

func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(maxi(0, y0), mini(SIZE - 1, y1) + 1):
		for x in range(maxi(0, x0), mini(SIZE - 1, x1) + 1):
			img.set_pixel(x, y, c)

## A convex fill: a pixel is inside when it sits on the same side of every edge.
func _poly(img: Image, points: Array, c: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			if _inside(Vector2(x, y), points):
				img.set_pixel(x, y, c)

func _inside(p: Vector2, points: Array) -> bool:
	var sign_seen := 0
	for i in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var cross := (b - a).cross(p - a)
		var s := 1 if cross > 0.0 else -1
		if sign_seen == 0:
			sign_seen = s
		elif s != sign_seen:
			return false
	return true

func _ellipse(img: Image, centre: Vector2, rx: float, ry: float, c: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var dx := (float(x) - centre.x) / rx
			var dy := (float(y) - centre.y) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c)

# ---------------------------------------------------------------------------
# The items
# ---------------------------------------------------------------------------

## A short haft under a heavy round head, which is the whole of what a mace is.
func _mace() -> Image:
	var img := _blank()
	_line(img, Vector2(64, 116), Vector2(64, 58), 5.0, DIM)
	_dot(img, Vector2(64, 44), 20.0, INK)
	for a in 8:
		var t := float(a) / 8.0 * TAU
		_dot(img, Vector2(64, 44) + Vector2(cos(t), sin(t)) * 24.0, 5.0, DIM)
	return img

## A cuff with a rune burning in the back of the hand.
func _rune_gauntlet() -> Image:
	var img := _blank()
	_rect(img, 34, 44, 94, 96, DIM)
	_rect(img, 28, 30, 100, 46, INK)
	_dot(img, Vector2(64, 70), 16.0, PLATE)
	_dot(img, Vector2(64, 70), 10.0, WARM)
	return img

## A long two-handed haft with a wide curved blade off the top of it.
func _reaper() -> Image:
	var img := _blank()
	_line(img, Vector2(80, 120), Vector2(88, 22), 5.0, DIM)
	for i in 40:
		var t := float(i) / 39.0
		var a := lerpf(-0.2, 2.6, t)
		_dot(img, Vector2(88, 24) + Vector2(cos(a), sin(a)) * 52.0, 5.5, INK)
	return img

## A short rod with a cold point, deliberately thinner than the staff.
func _wand() -> Image:
	var img := _blank()
	_line(img, Vector2(38, 100), Vector2(84, 44), 4.0, DIM)
	_poly(img, [Vector2(92, 22), Vector2(104, 40), Vector2(92, 58), Vector2(80, 40)], INK)
	return img

## A tall banded slab, square-shouldered where the old round shield was a kite.
func _tower_shield() -> Image:
	var img := _blank()
	_poly(img, [Vector2(34, 26), Vector2(94, 26), Vector2(94, 92), Vector2(64, 112), Vector2(34, 92)], DIM)
	_rect(img, 34, 44, 94, 52, INK)
	_rect(img, 34, 70, 94, 78, INK)
	return img

## A pole with a pennant streaming off one side of it.
func _standard() -> Image:
	var img := _blank()
	_line(img, Vector2(40, 118), Vector2(40, 16), 5.0, DIM)
	_poly(img, [Vector2(44, 22), Vector2(104, 36), Vector2(44, 64)], INK)
	_dot(img, Vector2(40, 12), 7.0, WARM)
	return img

## A propped open book: two leaves meeting at a spine.
func _book() -> Image:
	var img := _blank()
	_poly(img, [Vector2(16, 40), Vector2(62, 52), Vector2(62, 106), Vector2(16, 92)], INK)
	_poly(img, [Vector2(112, 40), Vector2(66, 52), Vector2(66, 106), Vector2(112, 92)], INK)
	_line(img, Vector2(64, 50), Vector2(64, 108), 3.0, DIM)
	return img

## A closed helm: a dome over a flat face with one visor slit across it.
func _great_helm() -> Image:
	var img := _blank()
	_ellipse(img, Vector2(64, 58), 34.0, 30.0, DIM)
	_rect(img, 30, 58, 98, 100, DIM)
	_rect(img, 38, 66, 90, 76, PLATE)
	_line(img, Vector2(64, 30), Vector2(64, 66), 3.0, INK)
	return img

## A drawn cowl: a peak falling to two shoulders with a dark face inside it.
func _hood() -> Image:
	var img := _blank()
	_poly(img, [Vector2(64, 16), Vector2(104, 78), Vector2(94, 110), Vector2(34, 110), Vector2(24, 78)], DIM)
	_ellipse(img, Vector2(64, 74), 20.0, 24.0, PLATE)
	return img

# ---------------------------------------------------------------------------
# The five empty plates, one outline each: #886 found two slots with no file at
# all, and greyscale has to separate every pair.
# ---------------------------------------------------------------------------

func _plate_diamond() -> Image:
	var img := _blank()
	_poly(img, [Vector2(64, 8), Vector2(112, 64), Vector2(64, 120), Vector2(16, 64)], PLATE)
	return img

func _plate_disc() -> Image:
	var img := _blank()
	_dot(img, Vector2(64, 64), 56.0, PLATE)
	return img

func _plate_arch() -> Image:
	var img := _blank()
	_ellipse(img, Vector2(64, 62), 52.0, 52.0, PLATE)
	_rect(img, 12, 62, 116, 114, PLATE)
	return img

func _plate_octagon() -> Image:
	var img := _blank()
	var pts: Array = []
	for i in 8:
		var a := float(i) / 8.0 * TAU + PI / 8.0
		pts.append(Vector2(64, 64) + Vector2(cos(a), sin(a)) * 58.0)
	_poly(img, pts, PLATE)
	return img

func _plate_ring() -> Image:
	var img := _blank()
	_dot(img, Vector2(64, 64), 56.0, PLATE)
	_dot(img, Vector2(64, 64), 30.0, Color(0, 0, 0, 0))
	return img

# ---------------------------------------------------------------------------

## The Standard's own action: a banner with a ring of ally marks around it.
func _rallying_cry() -> Image:
	var img := _blank()
	_line(img, Vector2(48, 116), Vector2(48, 26), 5.0, DIM)
	_poly(img, [Vector2(52, 30), Vector2(106, 44), Vector2(52, 68)], WARM)
	for i in 6:
		var a := float(i) / 6.0 * TAU
		_dot(img, Vector2(64, 74) + Vector2(cos(a), sin(a)) * 44.0, 6.0, INK)
	return img
