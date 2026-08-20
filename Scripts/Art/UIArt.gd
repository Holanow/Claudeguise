extends RefCounted
class_name UIArt


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
		_cache[path] = load_png(path)
	return _cache[path]

static func has_art(name: StringName) -> bool:
	return texture_for(name) != null

## ---------------------------------------------------------------------------
## THEMING, issue #115: "We should have some UI theming while art is going on.
## Borders and backgrounds for the major elements mostly."
##
## Two things this half has to get right that the icon half did not.
##
## 1. THE SCREENS DO NOT DRAW THEIR CHROME IN `_draw()`. `PartySelect`,
##    `InspectPanel`, `CombatLogView`, `FloorMapView`, `Main`, `GlossaryTooltip`
##    and the three level-editor views build it out of `ColorRect` backdrops and
##    `StyleBoxFlat` panels, which are Control-node theming and not canvas
##    drawing. `draw_border` cannot reach any of them. So the pipeline has to
##    hand back a NODE and a STYLEBOX, not only a draw call -- otherwise every
##    call site has to be rewritten into `_draw()` first, which is a large change
##    to somebody else's screens for no benefit the player asked for.
##
## 2. ONE FILE THEMES EVERYTHING; A SECOND FILE THEMES ONE THING. Every lookup
##    here is two-level. `panel_style(&"inspect_panel", ...)` asks for
##    `Assets/UI/panel/inspect_panel.png` first and `Assets/UI/panel.png` second,
##    so dropping in one `panel.png` re-skins every panel in the game at once,
##    and adding `panel/inspect_panel.png` later overrides that one without
##    disturbing the rest. Neither step is a code change. A pipeline that only
##    did the specific version would need seventeen files before anything
##    looked different, and one that only did the general version could never
##    make one panel special.
##
## ---------------------------------------------------------------------------
## AND THE RULE THAT MATTERS MORE THAN EITHER
##
## **A picture may replace decoration. A picture may not replace information.**
##
## `PartyCard` found this first: a nine-slice is drawn as painted, so a
## dropped-in border cannot carry state, and dropping one in would have silently
## deleted the only signal saying which four pawns the player had picked. The fix
## was to keep drawing the selection ring inside the border, asking `has_art`.
##
## `EquipmentIcons` then hit the same thing independently -- a dropped-in item
## PNG was deleting the badge that says an item teaches an ability -- so the
## corner badge is now drawn over dropped-in art rather than instead of it.
##
## Two systems, same failure, neither found by looking at the default. **It is
## invisible to a screenshot**, which is this project's main instrument: theming
## that has eaten a state signal renders perfectly. So before theming anything,
## ask what its border or background says besides "here is an edge" -- selected,
## focused, disabled, active, damaged -- and if it says something, keep saying it.

## The name a two-level lookup resolves to, or `&""` when neither file exists.
## Specific first, general second.
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
##
## Public because a caller has to be able to ask. `PartyCard` asks in order to
## keep drawing its selection ring when the border can no longer carry it, and
## that question has to be asked of the name the border really resolves to --
## asking about a different name is the "measurement one file over" failure this
## project keeps paying for.
##
## `panel_border` rather than `border` as the general name, because that is what
## `Assets/UI/README.md` has told the player since #81 and a rename would break
## a promise already made in writing.
static func border_art_name(element: StringName) -> StringName:
	if element != &"":
		var specific := StringName("border/%s" % element)
		if has_art(specific):
			return specific
	if has_art(&"panel_border"):
		return &"panel_border"
	return &""

## A `StyleBox` for a panel, card, tooltip or chip.
##
## With no file present this is a `StyleBoxFlat` in exactly the colours the
## caller passes -- the same object those screens build by hand today, so
## swapping a call site over changes no pixels. `PartyCard` set that precedent
## and it is what makes this safe to do across nine screens at once.
##
## With `Assets/UI/panel/<element>.png` or `Assets/UI/panel.png` present it is a
## nine-sliced `StyleBoxTexture`, so corners stay corners at any panel size.
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
##
## With no file present this is the `ColorRect` those screens already build, in
## the colour the caller passes. With `Assets/UI/background/<element>.png` or
## `Assets/UI/background.png` present it is a `TextureRect` set to COVER the
## rect, not to fit inside it.
##
## Cover and not fit, deliberately, and it is the one place this file departs
## from `draw_fit`. An icon that does not quite fill its box looks slightly
## small; a background that does not quite fill its screen has bars down the
## sides, which looks broken. A background is the one element where cropping is
## the correct compromise and letterboxing is not.
##
## The returned node is anchored full-rect and does not eat mouse input, because
## a background that swallows clicks is a screen whose buttons stop working --
## and that failure looks exactly like the buttons being broken.
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
##
## Public and here rather than private and duplicated: `UnitArt` needs exactly
## the same loader for `Assets/Units`, and it had its own byte-identical copy
## until issue #85. The reason it cannot be `load()` is in this file's header
## and in `UnitArt`'s -- Godot only produces a loadable texture for an image the
## editor has imported, and the editor does not run on this machine.
static func load_png(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		push_error("UIArt: %s exists but could not be read as an image" % path)
		return null
	return ImageTexture.create_from_image(image)

## A filled polygon with its own outline closed back to the first point.
##
## Four files drew this by hand -- `Silhouettes.draw_unit`, `AttackFX.
## draw_projectile`, `StatusIcons.draw_status` and `ActionIcons.draw_action` --
## each with its own `duplicate()` / `append(points[0])` pair, because Godot's
## `draw_polyline` does not close a loop and a polygon without the closing
## segment is missing exactly one edge. That is a defect nobody sees on the
## shape they were looking at and everybody ships on the next one.
##
## `fill` may be transparent, for the parts of a silhouette that are outline
## only.
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
##
## Nine-slice rather than `draw_fit` because a border is the one piece of
## interface art that must stretch non-uniformly, and stretching a decorated
## frame uniformly is the failure everybody hits first.
##
## `element` is the two-level half added for #115: `border/arena.png` themes one
## border and `panel_border.png` themes every border, and neither is a code
## change. Optional and trailing, so the two existing call sites are untouched --
## `panel_border.png` keeps meaning exactly what `Assets/UI/README.md` has been
## telling the player it means since #81.
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
## Player's ruling, 2026-08-19: *"we should do basically 0 drawing with code
## ever"*.
