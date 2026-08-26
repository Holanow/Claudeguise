extends RefCounted
class_name UnitArt


## A unit is a stack of part sprites, one slot at a time. Nothing is composited.
##
## Every part in `Assets/Units/parts/` is authored on the same square canvas,
## already in its place, and already carries its own outline ring. So a body is
## the parts its recipe names, drawn in slot order, each tinted by the recipe.

const PARTS_DIR := "res://Assets/Units/parts"

## Part textures live for the process, and one part is shared by every recipe
## that names it on both sides. This is the whole memory argument for slots:
## `hands` is one texture whatever wears it.
static var _parts: Dictionary = {}

static func part_texture(part: StringName) -> Texture2D:
	if _parts.has(part):
		return _parts[part]
	var tex := UIArt.load_png("%s/%s.png" % [PARTS_DIR, part])
	_parts[part] = tex
	return tex

## What one body is made of: the recipe's layers in slot draw order, each with
## the texture it draws and the colour it draws in. The one place a recipe turns
## into something drawable, so the arena's sprite tree and the immediate-mode
## draw below cannot disagree about what a unit looks like.
static var _sprites: Dictionary = {}

static func sprites_for(shape_id: StringName, team: CG.Team) -> Array:
	var key := "%s|%d" % [shape_id, int(team)]
	if _sprites.has(key):
		return _sprites[key]
	var out: Array = []
	for entry in UnitRecipes.slots_for(shape_id):
		for layer in entry["layers"]:
			out.append({
				"slot": entry["slot"],
				"part": layer["part"],
				"tex": part_texture(layer["part"]),
				"color": UnitRecipes.layer_color(layer, team),
			})
	_sprites[key] = out
	return out

## Only the tests need this: they check what a cache holds after the files under
## it change, and a cache populated before that change would hide it.
static func clear_cache() -> void:
	_parts.clear()
	_sprites.clear()
	_used_cache.clear()
	_top_cache.clear()
	_body_cache.clear()

static func has_art(shape_id: StringName, team: CG.Team) -> bool:
	return not sprites_for(shape_id, team).is_empty()

## Issue 589. Which chunk of a body a part leaves with when the body comes apart:
## the slot it is drawn in. A part in no slot lands in `Extra` and flies on its
## own, which is the property a hat leaving with the wrong chunk once broke.
static func fragments_for(shape_id: StringName, team: CG.Team) -> Array:
	var out: Array = []
	for entry in UnitRecipes.slots_for(shape_id):
		if entry["layers"].is_empty():
			continue
		var pieces: Array = []
		for layer in entry["layers"]:
			var tex := part_texture(layer["part"])
			if tex == null:
				return []
			pieces.append({"tex": tex, "color": UnitRecipes.layer_color(layer, team)})
		out.append({"group": entry["slot"], "pieces": pieces})
	# One chunk is the whole body, and a body that flies in one piece has not come
	# apart.
	return out if out.size() >= 2 else []

## The square canvas every part is authored on, read off a part rather than
## assumed, so changing `BakeParts.N` needs no edit here. Zero when no part loads.
static func canvas_size(shape_id: StringName, team: CG.Team) -> float:
	for s in sprites_for(shape_id, team):
		if s["tex"] != null:
			return float(maxf(s["tex"].get_width(), s["tex"].get_height()))
	return 0.0

static func draw(canvas: CanvasItem, tex: Texture2D, radius: float, facing_left: bool, center: Vector2 = Vector2.ZERO) -> void:
	var size := Vector2(tex.get_width(), tex.get_height())
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# Real art here is pixel art, drawn small and scaled up a lot -- the project's
	# default filtering is linear, which blurs it into a smudge at the sizes a pawn
	# is actually drawn at.
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw_texture_rect(tex, signed_rect(tex, radius, facing_left, center), false)

static func signed_rect(tex: Texture2D, radius: float, facing_left: bool, center: Vector2 = Vector2.ZERO) -> Rect2:
	var size := Vector2(tex.get_width(), tex.get_height())
	var drawn := size * ((radius * 2.0) / maxf(size.x, size.y))
	var rect := Rect2(center - drawn * 0.5, drawn)
	if facing_left:
		rect.size.x = -drawn.x
	return rect

## The rectangle a single texture actually puts ink in, in the local space it is
## drawn into: its **opaque** pixels, not its file dimensions.
static func opaque_rect(canvas_radius: float, tex: Texture2D, center: Vector2 = Vector2.ZERO) -> Rect2:
	var size := Vector2(tex.get_width(), tex.get_height())
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2(center, Vector2.ZERO)
	return _scaled(_used_rect(tex), size, canvas_radius, center)

## A used rect in texture pixels, in the local space a body is drawn into. The
## scale is the one `draw` uses: the longest side of the FILE spans the diameter,
## and `draw` centres the whole file on `center`.
static func _scaled(used: Rect2i, size: Vector2, canvas_radius: float, center: Vector2) -> Rect2:
	var scale := (canvas_radius * 2.0) / maxf(size.x, size.y)
	var origin := (Vector2(used.position) - size * 0.5) * scale
	return Rect2(origin + center, Vector2(used.size) * scale)

## **The union of the visible slot sprites**, which is the number every bar,
## badge, plate and marker sizes off. Issue 190: a 15px goblin wore a 90px health
## bar because decoration was sized from the simulation's collision radius, and
## this is where the drawing's own size comes from instead.
##
## The union rather than any one part: a Rat King's crown is the top of it and its
## tail is the left of it, and neither is the body.
static var _body_cache: Dictionary = {}

static func body_used_rect(shape_id: StringName, team: CG.Team) -> Rect2i:
	var key := "%s|%d" % [shape_id, int(team)]
	if _body_cache.has(key):
		return _body_cache[key]
	var union := Rect2i()
	var any := false
	for s in sprites_for(shape_id, team):
		var tex: Texture2D = s["tex"]
		if tex == null:
			continue
		var used := _used_rect(tex)
		union = used if not any else union.merge(used)
		any = true
	_body_cache[key] = union
	return union

## `body_used_rect` in the local space the body is drawn into.
static func body_rect(shape_id: StringName, team: CG.Team, radius: float, center: Vector2 = Vector2.ZERO) -> Rect2:
	var n := canvas_size(shape_id, team)
	if n <= 0.0:
		return Rect2(center, Vector2.ZERO)
	return _scaled(body_used_rect(shape_id, team), Vector2(n, n), radius, center)

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

## The same, for a whole body: the highest ink any of its parts puts in each
## column. A crown is the top of the column it sits in, and the head under it is
## not.
static func body_column_tops(shape_id: StringName, team: CG.Team) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(canvas_size(shape_id, team))
	if n <= 0:
		return out
	out.resize(n)
	out.fill(INF)
	for s in sprites_for(shape_id, team):
		var tex: Texture2D = s["tex"]
		if tex == null:
			continue
		var tops := column_tops(tex)
		for x in mini(n, tops.size()):
			if tops[x] < out[x]:
				out[x] = tops[x]
	return out

## One texture's opaque bounds as a fraction of the footprint it is drawn into.
static func texture_fraction(tex: Texture2D) -> Vector2:
	var longest := maxf(tex.get_width(), tex.get_height())
	if longest <= 0.0:
		return Vector2.ZERO
	return Vector2(_used_rect(tex).size) / longest

## `body_used_rect` as a fraction of the footprint the unit is drawn into.
static func opaque_fraction(shape_id: StringName, team: CG.Team) -> Vector2:
	var n := canvas_size(shape_id, team)
	if n <= 0.0:
		return Vector2.ZERO
	return Vector2(body_used_rect(shape_id, team).size) / n

## Opaque bounds per texture, cached beside the textures themselves. `get_image`
## copies the whole image out of the texture, so calling this per unit per frame
## would be the same mistake `_parts` above exists to avoid, one level down.
static var _used_cache: Dictionary = {}

static func _used_rect(tex: Texture2D) -> Rect2i:
	var key := tex.get_instance_id()
	if _used_cache.has(key):
		return _used_cache[key]
	var image := tex.get_image()
	# A fully transparent image has no used rect at all. Fall back to the whole
	# file rather than to nothing: a zero-size extent would silently collapse every
	# bar sized from it.
	var used := image.get_used_rect() if image != null else Rect2i()
	if used.size.x <= 0 or used.size.y <= 0:
		used = Rect2i(0, 0, tex.get_width(), tex.get_height())
	_used_cache[key] = used
	return used
