extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")

## The interface half of the drop-in art pipeline. PLAYTEST-NOTES-2 item 15:
##
##   "There must be a way to drop in artier UI elements later -- borders, icons.
##    Unit art already works this way: a PNG in Assets/Units/ replaces a unit
##    with no code change, no import, no registration. The interface has no
##    equivalent."
##
## This is that equivalent. `Scripts/Art/UnitArt.gd` does it for units; this does
## it for everything else, and `StatusIcons.gd` and `ActionIcons.gd` are its
## first two consumers rather than a test being its only one.
##
## MANAGER-OWNED (`Scripts/Art/**`).
##
## ---------------------------------------------------------------------------
## HOW TO REPLACE ANY PIECE OF INTERFACE ART
##
## Drop a PNG into `Assets/UI/` under the name the code asks for:
##
##     Assets/UI/status/bleed.png            one status badge
##     Assets/UI/action/warrior_execute.png  one ability icon
##     Assets/UI/panel_border.png            the border around panels
##
## That is the whole procedure. No code change, no scene edit, no re-import, no
## registration step. `Assets/UI/README.md` lists every name the game currently
## looks for, and `Tests/test_art.gd` keeps that list honest.
##
## Every drawing function here works with no files on disk at all -- that is the
## normal case today. A missing file means "draw the generated default", which
## is not an error and is never logged as one. A caller never asks whether a
## file exists.
##
## ---------------------------------------------------------------------------
## WHY IT LOADS IMAGES THE UNUSUAL WAY
##
## Same reason as `UnitArt.gd`, and the comment there has the measurement:
## `load()` cannot produce a texture for a PNG the editor has never imported,
## the editor does not run on this machine, and `Image.load()` works anyway. The
## consequence is the property that makes this a drop-in at all -- it works
## whether or not anything has ever been imported.

const ART_DIR := "res://Assets/UI"

## Textures live for the process, same as UnitArt's cache and for the same
## reason. Null is cached too: a miss is the common case and re-stat'ing a file
## that is not there, once per icon per frame, would be the expensive half.
static var _cache: Dictionary = {}

## The texture dropped in under `name`, or null when there is no file for it.
## `name` may contain a slash: `&"status/bleed"` reads `Assets/UI/status/bleed.png`.
static func texture_for(name: StringName) -> Texture2D:
	var path := "%s/%s.png" % [ART_DIR, name]
	if not _cache.has(path):
		_cache[path] = _load(path)
	return _cache[path]

static func has_art(name: StringName) -> bool:
	return texture_for(name) != null

## Forget everything loaded so far. Only the tests need this -- they write a
## file into `Assets/UI` to prove the drop-in end to end, and a cache populated
## before that write would hide it.
static func clear_cache() -> void:
	_cache.clear()

static func _load(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		push_error("UIArt: %s exists but could not be read as an image" % path)
		return null
	return ImageTexture.create_from_image(image)

## Draws `tex` centred in `rect`, scaled so its longest side spans the shorter
## side of the rect. Aspect is preserved: a squashed icon reads as a bug and a
## slightly small one does not. Same reasoning and same nearest filtering as
## `UnitArt.draw`, because dropped-in interface art is pixel art too.
static func draw_fit(canvas: CanvasItem, tex: Texture2D, rect: Rect2) -> void:
	var size := Vector2(tex.get_width(), tex.get_height())
	if size.x <= 0.0 or size.y <= 0.0:
		return
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var scale := minf(rect.size.x, rect.size.y) / maxf(size.x, size.y)
	var drawn := size * scale
	canvas.draw_texture_rect(tex, Rect2(rect.get_center() - drawn * 0.5, drawn), false)

## A border around `rect`. With `Assets/UI/panel_border.png` present it is drawn
## as a nine-slice so corners stay corners at any panel size; with no file it is
## the flat one-pixel outline the caller would have written by hand.
##
## Nine-slice rather than `draw_fit` because a border is the one piece of
## interface art that must stretch non-uniformly, and stretching a decorated
## frame uniformly is the failure everybody hits first.
static func draw_border(canvas: CanvasItem, rect: Rect2, fallback: Color, thickness: float = 1.0) -> void:
	var tex := texture_for(&"panel_border")
	if tex == null:
		canvas.draw_rect(rect, fallback, false, thickness)
		return
	draw_nine_slice(canvas, tex, rect)

## Nine-slice a texture across `rect`. The corner size is a third of the
## texture's shorter side, which is the convention a border PNG should be drawn
## to: a 24x24 file has 8px corners.
static func draw_nine_slice(canvas: CanvasItem, tex: Texture2D, rect: Rect2) -> void:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	if tw <= 0.0 or th <= 0.0:
		return
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var c := floorf(minf(tw, th) / 3.0)
	# A rect smaller than two corners would draw the corners overlapping and
	# inside out. Clamp instead, so a tight panel loses border detail rather
	# than rendering garbage.
	var dc := minf(c, minf(rect.size.x, rect.size.y) * 0.5)
	var src_x := [0.0, c, tw - c]
	var src_w := [c, tw - c * 2.0, c]
	var src_y := [0.0, c, th - c]
	var src_h := [c, th - c * 2.0, c]
	var dst_x := [rect.position.x, rect.position.x + dc, rect.end.x - dc]
	var dst_w := [dc, rect.size.x - dc * 2.0, dc]
	var dst_y := [rect.position.y, rect.position.y + dc, rect.end.y - dc]
	var dst_h := [dc, rect.size.y - dc * 2.0, dc]
	for i in 3:
		for j in 3:
			if src_w[i] <= 0.0 or src_h[j] <= 0.0 or dst_w[i] <= 0.0 or dst_h[j] <= 0.0:
				continue
			canvas.draw_texture_rect_region(
				tex,
				Rect2(dst_x[i], dst_y[j], dst_w[i], dst_h[j]),
				Rect2(src_x[i], src_y[j], src_w[i], src_h[j]))

## ---------------------------------------------------------------------------
## GENERATED GLYPHS
##
## The defaults a dropped-in PNG replaces. A glyph is an Array of parts, each a
## Dictionary with exactly one shape key:
##
##     {"poly": [[x, y], ...]}                filled polygon
##     {"line": [[x, y], ...], "w": 0.18}     stroked polyline
##     {"arc":  [cx, cy, r], "w": 0.18}       stroked circle
##     {"arc":  [cx, cy, r, from, to], ...}   stroked partial arc, radians
##     {"dot":  [cx, cy, r]}                  filled circle
##
## Any part may also carry `"rot": <radians>`, rotating it about the glyph's
## centre. It exists because an upright sword drawn thin enough to be a sword
## reads as a plus sign, and tilting it fixes that completely -- measured on the
## first rendered sheet, where `warrior_strike` and `priest_heal` came out as
## the same cross. Authoring a shape upright and tilting it beats hand-computing
## rotated vertices and getting them slightly wrong.
##
## Coordinates are in a -1..1 box with +Y down and stroke widths in the same
## units, so one glyph scales to any icon size. Same convention as
## `AttackFX._PROJECTILE_SHAPES`, deliberately, so the two files read alike.
##
## Geometry is data and the draw call is a loop over it, for the reason
## `Silhouettes.build_parts` is split from `Silhouettes.draw_unit`: Godot
## refuses `draw_*` outside `_draw()`, so a test that can only call the drawing
## wrapper logs a wall of errors and asserts nothing.

## Points of one `poly` or `line` part mapped into `rect`. Split out so a test
## can check a glyph lands inside its own box without a live canvas.
static func glyph_points(part: Dictionary, rect: Rect2) -> PackedVector2Array:
	var center := rect.get_center()
	var half := minf(rect.size.x, rect.size.y) * 0.5
	var raw: Array = part.get("poly", part.get("line", []))
	var rot := float(part.get("rot", 0.0))
	var out := PackedVector2Array()
	for p in raw:
		var v := Vector2(p[0], p[1])
		if rot != 0.0:
			v = v.rotated(rot)
		out.append(center + v * half)
	return out

## Where a `dot` or `arc` part's centre lands, honouring the same `rot`.
static func glyph_center(part: Dictionary, at: Array, rect: Rect2) -> Vector2:
	var v := Vector2(at[0], at[1])
	var rot := float(part.get("rot", 0.0))
	if rot != 0.0:
		v = v.rotated(rot)
	return rect.get_center() + v * minf(rect.size.x, rect.size.y) * 0.5

static func _stroke(part: Dictionary, half: float) -> float:
	# Never below a pixel: a 0.18-unit stroke on a 12px icon is 1.08px, and the
	# next size down would vanish entirely rather than merely thin out.
	return maxf(1.0, float(part.get("w", 0.18)) * half)

static func draw_glyph(canvas: CanvasItem, glyph: Array, rect: Rect2, color: Color) -> void:
	var half := minf(rect.size.x, rect.size.y) * 0.5
	for part in glyph:
		if part.has("poly"):
			canvas.draw_colored_polygon(glyph_points(part, rect), color)
		elif part.has("line"):
			canvas.draw_polyline(glyph_points(part, rect), color, _stroke(part, half), true)
		elif part.has("dot"):
			var d: Array = part["dot"]
			canvas.draw_circle(glyph_center(part, d, rect), d[2] * half, color)
		elif part.has("arc"):
			var a: Array = part["arc"]
			var rot := float(part.get("rot", 0.0))
			var from := (float(a[3]) if a.size() > 3 else 0.0) + rot
			var to := (float(a[4]) if a.size() > 4 else TAU) + rot
			canvas.draw_arc(glyph_center(part, a, rect), a[2] * half, from, to, 24, color, _stroke(part, half), true)
