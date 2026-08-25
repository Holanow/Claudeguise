extends Node2D

## Issue 572, and issue 280's rule applied: the mark that shipped as a polygon
## and the mark that ships as a PNG, rasterised side by side at the size the
## arena actually draws them, with the pixels counted rather than glanced at.
##
## The trap #280 was written for is a test that measures drawn geometry and
## keeps passing after that geometry stops being what ships. So this compares
## PIXELS, and the polygon half is a local copy: the game no longer has one.

const CAPTURE_PATH := "res://Tools/preview/projectiles.png"

## What `ArenaFloor` passes, and the scale `BattleView` puts the arena at on a
## 1280x720 window. Asked of both rather than retyped.
const ARENA_SIZE := 15.0
const WINDOW := Vector2(1280.0, 720.0)

const _CELL := Vector2(150.0, 130.0)
const _MARGIN := Vector2(60.0, 110.0)
const _ZOOM := 6.0

func _ready() -> void:
	if not Offscreen.require_renderer(self):
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_report()
	_capture()
	get_tree().quit(0)

static func _screen_half() -> float:
	var layout: Dictionary = BattleView.compute_layout(WINDOW)
	var scale: Vector2 = layout["scale"]
	return ARENA_SIZE * scale.x

func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Tools/preview"))
	var err := image.save_png(CAPTURE_PATH)
	if err != OK:
		printerr("ProjectileShot: could not save %s (error %d)" % [CAPTURE_PATH, err])
		return
	print("ProjectileShot: wrote ", CAPTURE_PATH)

## What the two halves actually differ by, per damage type, at true size. Read
## off the rendered frame, so it is the shipped path being measured.
func _report() -> void:
	var half := _screen_half()
	print("ProjectileShot: a mark is %.1f px across on a %dx%d window" % [
		half * 2.0, int(WINDOW.x), int(WINDOW.y)])
	var frame := get_viewport().get_texture().get_image()
	var box := int(ceil(half * 2.0)) + 4
	for i in AttackFX.damage_types().size():
		var drawn := _crop(frame, _centre(i, 0), box)
		var baked := _crop(frame, _centre(i, 1), box)
		var differing := 0
		var lit := 0
		for y in box:
			for x in box:
				var a := drawn.get_pixel(x, y)
				var b := baked.get_pixel(x, y)
				if a.a > 0.0 or b.a > 0.0:
					lit += 1
				if a != b:
					differing += 1
		print("  %-10s %d of %d pixels differ" % [
			String(CG.DamageType.keys()[AttackFX.damage_types()[i]]).to_lower(), differing, lit])

func _crop(frame: Image, centre: Vector2, box: int) -> Image:
	var origin := Vector2i(centre) - Vector2i(box, box) / 2
	origin = origin.clamp(Vector2i.ZERO, frame.get_size() - Vector2i(box, box))
	return frame.get_region(Rect2i(origin, Vector2i(box, box)))

## Where one mark sits: a column per damage type, row 0 the polygon and row 1
## the sprite, both at true size. The zoomed pair sits below them.
func _centre(index: int, row: int) -> Vector2:
	return _MARGIN + Vector2(float(index) * _CELL.x, float(row) * 40.0)

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var half := _screen_half()
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Palette.BACKGROUND)
	draw_string(font, Vector2(_MARGIN.x, 44.0),
		"In-flight projectile marks: the polygon that shipped, and the PNG that replaces it",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_HEADING, Palette.TEXT)
	draw_string(font, Vector2(_MARGIN.x, 68.0),
		"row 1: drawn in code  ·  row 2: %s  ·  both at the true %.1f px  ·  below: the same pair at %dx" % [
			"Assets/UI/projectile/*.png", half * 2.0, int(_ZOOM)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	var types := AttackFX.damage_types()
	for i in types.size():
		var dt: CG.DamageType = types[i]
		_polygon(_centre(i, 0), half, dt)
		AttackFX.draw_projectile(self, _centre(i, 1), Vector2.RIGHT, dt, half)

		var zoom_top := _MARGIN + Vector2(float(i) * _CELL.x, 150.0)
		_polygon(zoom_top, half * _ZOOM, dt)
		AttackFX.draw_projectile(self, zoom_top + Vector2(0.0, half * _ZOOM * 2.4), Vector2.RIGHT, dt, half * _ZOOM)
		draw_string(font, zoom_top + Vector2(-30.0, half * _ZOOM * 4.0),
			String(CG.DamageType.keys()[dt]).to_lower(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

## The draw that shipped before this issue, kept here and nowhere else: the
## before half of a before-and-after cannot live in the after.
func _polygon(at: Vector2, size: float, dt: CG.DamageType) -> void:
	var points := AttackFX.projectile_points(dt, size, Vector2.RIGHT)
	for i in points.size():
		points[i] += at
	UIArt.draw_outlined_polygon(self, points, Palette.damage_color(dt), Palette.ARENA_EDGE, 1.0)
