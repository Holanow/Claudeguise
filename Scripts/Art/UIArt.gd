extends RefCounted
class_name UIArt


## The interface half of the drop-in art pipeline. `UnitArt.gd` does it for
## units; this does it for everything else.
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
		_cache[path] = load_png(path)
	return _cache[path]

static func has_art(name: StringName) -> bool:
	return texture_for(name) != null

## ---------------------------------------------------------------------------
## THEMING
##
## The screens build their chrome from `ColorRect` backdrops and
## `StyleBoxFlat` panels rather than `_draw()`, so this half hands back a
## NODE and a STYLEBOX, not only a draw call.
static func theme_name(kind: StringName, element: StringName) -> StringName:
	if element != &"":
		var specific := StringName("%s/%s" % [kind, element])
		if has_art(specific):
			return specific
	if has_art(kind):
		return kind
	return &""

## What `draw_border` will actually use, or `&""` when it will draw the flat
## fallback.
static func border_art_name(element: StringName) -> StringName:
	if element != &"":
		var specific := StringName("border/%s" % element)
		if has_art(specific):
			return specific
	if has_art(&"panel_border"):
		return &"panel_border"
	return &""

## A `StyleBox` for a panel, card, tooltip or chip.
static func panel_style(element: StringName, bg: Color, border: Color, thickness: int = 1, margin: float = 0.0) -> StyleBox:
	var name := theme_name(&"panel", element)
	if name != &"":
		var tex := texture_for(name)
		var style := StyleBoxTexture.new()
		style.texture = tex
		# The same corner convention `draw_nine_slice` uses and that
		# `Assets/UI/README.md` documents: a third of the shorter side, so a
		# 24x24 file has 8px corners and one file works at every panel size.
		var c := floorf(minf(tex.get_width(), tex.get_height()) / 3.0)
		style.texture_margin_left = c
		style.texture_margin_right = c
		style.texture_margin_top = c
		style.texture_margin_bottom = c
		if margin > 0.0:
			style.set_content_margin_all(margin)
		return style
	var flat := StyleBoxFlat.new()
	flat.bg_color = bg
	flat.border_color = border
	flat.set_border_width_all(thickness)
	if margin > 0.0:
		flat.set_content_margin_all(margin)
	return flat

## A full-bleed background for a screen.
static func background_node(element: StringName, fallback: Color) -> Control:
	var name := theme_name(&"background", element)
	var node: Control
	if name != &"":
		var rect := TextureRect.new()
		rect.texture = texture_for(name)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		node = rect
	else:
		var flat := ColorRect.new()
		flat.color = fallback
		node = flat
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

## The `_draw()` equivalent of `background_node`, for the canvas-drawn screens.
## `ArenaFloor` is the one that has this shape today.
static func draw_background(canvas: CanvasItem, rect: Rect2, element: StringName, fallback: Color) -> void:
	var name := theme_name(&"background", element)
	var tex := texture_for(name) if name != &"" else null
	if tex == null:
		canvas.draw_rect(rect, fallback)
		return
	draw_cover(canvas, tex, rect)

## Draws `tex` filling `rect` completely, cropping whichever axis overflows.
## The counterpart to `draw_fit`, which letterboxes instead. See
## `background_node` for why a background wants this one.
static func draw_cover(canvas: CanvasItem, tex: Texture2D, rect: Rect2) -> void:
	var size := Vector2(tex.get_width(), tex.get_height())
	if size.x <= 0.0 or size.y <= 0.0:
		return
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var scale := maxf(rect.size.x / size.x, rect.size.y / size.y)
	var drawn := size * scale
	# The source region that survives the crop, so the middle of the image stays
	# in the middle of the screen rather than the top left.
	var src := Rect2(
		(drawn - rect.size) * 0.5 / scale,
		rect.size / scale)
	canvas.draw_texture_rect_region(tex, rect, src)

## Forget everything loaded so far. Only the tests need this -- they write a
## file into `Assets/UI` to prove the drop-in end to end, and a cache populated
## before that write would hide it.
static func clear_cache() -> void:
	_cache.clear()

## Reads a PNG off disk into a texture, or null when there is no file there. A
## missing file is the normal case and is silent; a file that exists and cannot
## be read is a real mistake and says so.
static func load_png(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		push_error("UIArt: %s exists but could not be read as an image" % path)
		return null
	return ImageTexture.create_from_image(image)

## A filled polygon with its own outline closed back to the first point.
static func draw_outlined_polygon(canvas: CanvasItem, points: PackedVector2Array, fill: Color, outline: Color, width: float) -> void:
	if points.size() < 2:
		return
	if fill.a > 0.0:
		canvas.draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	canvas.draw_polyline(closed, outline, width, true)

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
static func draw_border(canvas: CanvasItem, rect: Rect2, fallback: Color, thickness: float = 1.0, element: StringName = &"") -> void:
	var name := border_art_name(element)
	var tex := texture_for(name) if name != &"" else null
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

## Glyph geometry used to live below this line: a part format, a points mapper
## and a `draw_glyph` loop, shared by the status, ability and item icons. All
## three now draw PNGs baked by `Tools/BakeGlyphs.tscn`, so it went with them. That tool is deleted too --
## `git log --diff-filter=D -- Tools/BakeGlyphs.gd`.
