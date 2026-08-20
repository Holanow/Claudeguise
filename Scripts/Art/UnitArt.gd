extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const UIArt := preload("res://Scripts/Art/UIArt.gd")

## Real art, if any exists, in place of the placeholder polygons.
##
## MANAGER-OWNED (`Scripts/Art/**`), and built to be thrown away by whoever

const ART_DIR := "res://Assets/Units"

## Textures live for the process. Loading a PNG per unit per frame would be a
## disaster and the failure would look like the game being slow rather than like
## a caching mistake.
static var _cache: Dictionary = {}

## The texture for a shape, or null when there is no file for it. Null is the
## normal case right now and is not an error: it means "use the placeholder".
static func texture_for(shape_id: StringName, team: CG.Team) -> Texture2D:
	var side := "player" if team == CG.Team.PLAYER else "enemy"
	# Side-specific first, then the shared file.
	for candidate in ["%s/%s.%s.png" % [ART_DIR, shape_id, side], "%s/%s.png" % [ART_DIR, shape_id]]:
		if _cache.has(candidate):
			if _cache[candidate] != null:
				return _cache[candidate]
			continue
		var tex := UIArt.load_png(candidate)
		_cache[candidate] = tex
		if tex != null:
			return tex
	return null

static func has_art(shape_id: StringName, team: CG.Team) -> bool:
	return texture_for(shape_id, team) != null

## Draws the texture centred on `center`, scaled so its longest side spans the
## unit's diameter. Aspect ratio is preserved: art that is taller than it is wide
## stays that way rather than being squashed into a square, because a squashed
static func draw(canvas: CanvasItem, tex: Texture2D, radius: float, facing_left: bool, center: Vector2 = Vector2.ZERO) -> void:
	var size := Vector2(tex.get_width(), tex.get_height())
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# Real art here is pixel art, drawn small and scaled up a lot -- the
	# project's default filtering is linear (nothing sets otherwise), which
	# blurs it into a smudge at the sizes a pawn is actually drawn. Nearest
	# keeps every pixel a pixel. This only affects this canvas's own texture
	# draws, so it is safe to set unconditionally: the polygon fallback below
	# never draws a texture and is untouched by it.
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw_texture_rect(tex, signed_rect(tex, radius, facing_left, center), false)

## The rect `draw` hands to `draw_texture_rect`, signed: `size.x` is negative
## when the sprite is mirrored. Split out of `draw` only so a test can assert
## the arithmetic without a renderer -- the gate is headless and reads back
static func signed_rect(tex: Texture2D, radius: float, facing_left: bool, center: Vector2 = Vector2.ZERO) -> Rect2:
	var size := Vector2(tex.get_width(), tex.get_height())
	var drawn := size * ((radius * 2.0) / maxf(size.x, size.y))
	var rect := Rect2(center - drawn * 0.5, drawn)
	if facing_left:
		rect.size.x = -drawn.x
	return rect

## The rectangle `draw` above actually puts ink in, in the same local space it
## draws into: the texture's **opaque** pixels, not its file dimensions.
static func opaque_rect(canvas_radius: float, tex: Texture2D, center: Vector2 = Vector2.ZERO) -> Rect2:
	var size := Vector2(tex.get_width(), tex.get_height())
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2(center, Vector2.ZERO)
	var used := _used_rect(tex)
	# Same scale `draw` uses: longest side of the FILE spans the diameter.
	var scale := (canvas_radius * 2.0) / maxf(size.x, size.y)
	# `used` is in texture pixels from the file's top-left; `draw` centres the
	# whole file on `center`, so shift by half the file before scaling.
	var origin := (Vector2(used.position) - size * 0.5) * scale
	return Rect2(origin + center, Vector2(used.size) * scale)

## The topmost opaque pixel of each texture column, in texture rows from the
## file's top. `INF` for a column with no opaque pixel at all.
static var _top_cache: Dictionary = {}

static func column_tops(tex: Texture2D) -> PackedFloat32Array:
	var key := tex.get_instance_id()
	if _top_cache.has(key):
		return _top_cache[key]
	var out := PackedFloat32Array()
	out.resize(tex.get_width())
	out.fill(INF)
	var image := tex.get_image()
	if image != null:
		for x in tex.get_width():
			for y in tex.get_height():
				if image.get_pixel(x, y).a > 0.0:
					out[x] = float(y)
					break
	_top_cache[key] = out
	return out

## `opaque_rect` as a fraction of the footprint the unit is drawn into, per axis.
##
## Computed from the integer pixel counts rather than by scaling and dividing
## back, so a sprite whose art is exactly half its file -- `priest.png` is 12
## opaque columns of 24 -- reports exactly 0.5 instead of 0.49999999999999994.
## A floor test on this value sits right on that boundary today.
static func opaque_fraction(tex: Texture2D) -> Vector2:
	var longest := maxf(tex.get_width(), tex.get_height())
	if longest <= 0.0:
		return Vector2.ZERO
	return Vector2(_used_rect(tex).size) / longest

## Opaque bounds per texture, cached beside the textures themselves. `get_image`
## copies the whole image out of the texture, so calling this per unit per frame
## would be the same mistake `_cache` above exists to avoid, one level down.
static var _used_cache: Dictionary = {}

static func _used_rect(tex: Texture2D) -> Rect2i:
	var key := tex.get_instance_id()
	if _used_cache.has(key):
		return _used_cache[key]
	var image := tex.get_image()
	# A fully transparent image has no used rect at all. Fall back to the whole
	# file rather than to nothing: a zero-size extent would silently collapse
	# every bar sized from it, which is a far more confusing failure than a
	# slightly generous box around art that draws nothing.
	var used := image.get_used_rect() if image != null else Rect2i()
	if used.size.x <= 0 or used.size.y <= 0:
		used = Rect2i(0, 0, tex.get_width(), tex.get_height())
	_used_cache[key] = used
	return used
