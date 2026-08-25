extends Node2D

## #280's rule applied: the mark that shipped as a polygon and the mark that
## ships as a PNG, rasterised side by side at the size the arena draws them,
## with the pixels counted rather than glanced at.

const CAPTURE_PATH := "res://Tools/preview/projectiles.png"

## What `ArenaFloor` passes, and the scale `BattleView` puts the arena at on a
## 1280x720 window. Asked of both rather than retyped.
const ARENA_SIZE := 15.0
const WINDOW := Vector2(1280.0, 720.0)

const _CELL := Vector2(150.0, 130.0)
const _MARGIN := Vector2(60.0, 110.0)
## Held so the widest mark at this zoom stays clear of the next column: at 6x a
## 24.8 px mark is 149 px wide in a 150 px cell and the crops read each other.
const _ZOOM := 5.0

func _ready() -> void:
	if not Offscreen.hide_window(self):
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

## The question this issue has to answer is whether the mark CHANGED SIZE, so
## it measures each half's ink box off the rendered frame rather than counting
## pixel inequality, which antialiasing alone moves.
func _report() -> void:
	var half := _screen_half()
	print("ProjectileShot: a mark spans %.1f px on a %dx%d window" % [
		half * 2.0, int(WINDOW.x), int(WINDOW.y)])
	var frame := get_viewport().get_texture().get_image()
	_rows(frame, "TRUE SIZE", int(ceil(half * 2.0)) + 8, _centre)
	_rows(frame, "AT %dx" % int(_ZOOM), int(ceil(half * 2.0 * _ZOOM)) + 8, _zoom_centre)

func _rows(frame: Image, title: String, box: int, at: Callable) -> void:
	print("  %s -- %-14s %-14s %s" % [title, "polygon w x h", "sprite w x h", "delta"])
	for i in AttackFX.damage_types().size():
		var drawn := _ink_box(_crop(frame, at.call(i, 0), box))
		var baked := _ink_box(_crop(frame, at.call(i, 1), box))
		print("    %-10s %-14s %-14s %+d x %+d px" % [
			String(CG.DamageType.keys()[AttackFX.damage_types()[i]]).to_lower(),
			"%d x %d" % [drawn.x, drawn.y], "%d x %d" % [baked.x, baked.y],
			baked.x - drawn.x, baked.y - drawn.y])

## The size of the smallest box holding every pixel that is not the backdrop.
func _ink_box(crop: Image) -> Vector2i:
	var lo := Vector2i(crop.get_size())
	var hi := Vector2i(-1, -1)
	for y in crop.get_height():
		for x in crop.get_width():
			var c := crop.get_pixel(x, y)
			if absf(c.r - Palette.BACKGROUND.r) + absf(c.g - Palette.BACKGROUND.g) + absf(c.b - Palette.BACKGROUND.b) < 0.02:
				continue
			lo = lo.min(Vector2i(x, y))
			hi = hi.max(Vector2i(x, y))
	if hi.x < lo.x:
		return Vector2i.ZERO
	return hi - lo + Vector2i.ONE

func _crop(frame: Image, centre: Vector2, box: int) -> Image:
	var origin := Vector2i(centre) - Vector2i(box, box) / 2
	origin = origin.clamp(Vector2i.ZERO, frame.get_size() - Vector2i(box, box))
	return frame.get_region(Rect2i(origin, Vector2i(box, box)))

## Where one mark sits: a column per damage type, row 0 the polygon and row 1
## the sprite, both at true size. The zoomed pair sits below them.
func _centre(index: int, row: int) -> Vector2:
	return _MARGIN + Vector2(float(index) * _CELL.x, float(row) * 40.0)

## The same pair at `_ZOOM`, where one pixel of antialiasing is a sixth of what
## it is above and a real change of geometry has nowhere to hide.
func _zoom_centre(index: int, row: int) -> Vector2:
	var top := _MARGIN + Vector2(float(index) * _CELL.x, 150.0)
	return top + Vector2(0.0, float(row) * _screen_half() * _ZOOM * 2.4)

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

		_polygon(_zoom_centre(i, 0), half * _ZOOM, dt)
		AttackFX.draw_projectile(self, _zoom_centre(i, 1), Vector2.RIGHT, dt, half * _ZOOM)
		draw_string(font, _zoom_centre(i, 0) + Vector2(-30.0, half * _ZOOM * 4.0),
			String(CG.DamageType.keys()[dt]).to_lower(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

## The draw that shipped before this issue, kept here and nowhere else.
func _polygon(at: Vector2, size: float, dt: CG.DamageType) -> void:
	var points := AttackFX.projectile_points(dt, size, Vector2.RIGHT)
	for i in points.size():
		points[i] += at
	UIArt.draw_outlined_polygon(self, points, Palette.damage_color(dt), Palette.ARENA_EDGE, 1.0)
