extends RefCounted
class_name UnitRecipes


## Issue 566. What a unit is made of, rather than a drawing of it.
##
## A recipe is a stack of parts from `Assets/Units/parts/`, bottom first, each
## with a colour. `compose` layers them into ONE texture per (shape, team) and
## caches it, so the arena still issues one `draw_texture_rect` per body.

const PARTS_DIR := "res://Assets/Units/parts"

## The colour every composed silhouette is outlined in. The existing sprites all
## carry a dark border and it is what keeps a body off the floor it stands on.
const OUTLINE := Color("14121a")

## The outline's width as a share of the canvas, so it survives the downsample.
## A unit is drawn at 20-60 screen pixels from a 256-pixel file, so a border
## authored at one pixel is gone by the time anybody sees it.
const OUTLINE_SHARE := 0.031

## `team` on a layer takes `Palette.team_color` instead of `color`, which is the
## one place a side changes what a unit looks like.
const RECIPES := {
	&"goblin": [
		{"part": &"body_skinny", "color": "5d7a3a"},
		{"part": &"hands", "color": "7fa050"},
		{"part": &"head_round", "color": "7fa050"},
		{"part": &"ears_pointed", "color": "6f8f4a"},
		{"part": &"nose_triangle", "color": "8fb45c"},
		{"part": &"eyes", "color": "1c1a12"},
	],
	## The player: "Don't put earss on aaything but the goblin." I read the
	## archer as the goblin, because it is the same creature with a hood on and
	## the sheet the ruling was made against showed both as goblins. Deleting one
	## line below takes the ears off it if that reading is wrong.
	&"goblin_archer": [
		{"part": &"body_skinny", "color": "4a6a52"},
		{"part": &"hands", "color": "7fa050"},
		{"part": &"head_round", "color": "7fa050"},
		{"part": &"ears_pointed", "color": "6f8f4a"},
		{"part": &"nose_triangle", "color": "8fb45c"},
		{"part": &"hood", "color": "3b5a44"},
		{"part": &"eyes", "color": "1c1a12"},
	],
	&"warrior": [
		{"part": &"body_muscular", "team": true},
		{"part": &"hands_wide", "color": "d8b48c"},
		{"part": &"head_round", "color": "d8b48c"},
		{"part": &"plume", "color": "b8503c"},
		{"part": &"eyes", "color": "1c1a12"},
	],
	&"abomination": [
		{"part": &"body_rotund", "color": "6b4a7a"},
		{"part": &"hands_wide", "color": "7c5a8c"},
		{"part": &"head_small", "color": "7c5a8c"},
		{"part": &"horns", "color": "d8cbe0"},
		{"part": &"tusks", "color": "d8cbe0"},
		{"part": &"eyes", "color": "e8d24a"},
	],
	&"priest": [
		{"part": &"body_skinny", "team": true},
		{"part": &"hands", "color": "e0c0a0"},
		{"part": &"head_round", "color": "e0c0a0"},
		{"part": &"hood", "color": "e8dcb0"},
		{"part": &"eyes", "color": "1c1a12"},
	],
	## No ears, twice over: `test_art.gd` caught round ears making the rat as tall
	## as it is wide, and the player has since ruled that nothing but the goblin
	## gets them at all.
	&"rat": [
		{"part": &"body_low", "color": "7a6a58"},
		{"part": &"tail", "color": "8a7a68"},
		{"part": &"head_snouted", "color": "8a7a68"},
		{"part": &"eyes_snout", "color": "c04a4a"},
	],
}

static func has_recipe(shape_id: StringName) -> bool:
	return RECIPES.has(shape_id)

static func recipe_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in RECIPES.keys():
		out.append(k)
	out.sort()
	return out

## One composed texture per (shape, team). Built once and kept for the process:
## the alternative is layering at draw time, which is the draw-call multiplier
## issue 566 was worried about and this avoids entirely.
static var _cache := {}

static func clear_cache() -> void:
	_cache.clear()
	_rings.clear()

static func compose(shape_id: StringName, team: CG.Team) -> Texture2D:
	var key := "%s|%d" % [shape_id, int(team)]
	if _cache.has(key):
		return _cache[key]
	var made := _build(shape_id, team)
	_cache[key] = made
	return made

## Part images live for the process too. A part is read by every recipe that
## names it, and `get_image` copies the whole file each time.
static var _part_images := {}

static func part_image(part: StringName) -> Image:
	if _part_images.has(part):
		return _part_images[part]
	var img: Image = null
	var path := "%s/%s.png" % [PARTS_DIR, part]
	if FileAccess.file_exists(path):
		var loaded := Image.new()
		if loaded.load(path) == OK:
			loaded.convert(Image.FORMAT_RGBA8)
			img = loaded
		else:
			push_error("UnitRecipes: %s exists but could not be read" % path)
	_part_images[part] = img
	return img

static func _build(shape_id: StringName, team: CG.Team) -> Texture2D:
	var img := compose_image(shape_id, team)
	return null if img == null else ImageTexture.create_from_image(img)

## The composed pixels. `Tools/BakeParts.gd` writes these to disk so the game
## never pays for the composition, and this is the one place it happens, so the
## baked file and the runtime fallback cannot disagree.
static func compose_image(shape_id: StringName, team: CG.Team) -> Image:
	var layers: Array = RECIPES.get(shape_id, [])
	if layers.is_empty():
		return null
	var size := _canvas_size(layers)
	if size <= 0:
		return null
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	# The player: "Every part needs to be outlined and heavier." So the ring is
	# per part rather than around the union -- a head now carries its own edge
	# where it crosses a body, which is where the weight comes from.
	var width := maxi(1, roundi(float(size) * OUTLINE_SHARE))
	for layer in layers:
		var part := part_image(layer["part"])
		# A missing part is a black square, per the player's ruling: an obvious
		# defect beats a silent hole in a body.
		if part == null:
			_fill_square(out, Color.BLACK)
			continue
		_stamp(out, part_ring(layer["part"], width), OUTLINE)
		_stamp(out, part, _layer_color(layer, team))
	return out

static func _layer_color(layer: Dictionary, team: CG.Team) -> Color:
	if layer.get("team", false):
		return Palette.team_color(team)
	return Color(layer.get("color", "ffffff"))

## Every part shares one canvas, so the composed size is simply the part size.
## Read off the first part that loads rather than assumed, so changing
## `BakeParts.N` needs no edit here.
static func _canvas_size(layers: Array) -> int:
	for layer in layers:
		var part := part_image(layer["part"])
		if part != null:
			return part.get_width()
	return 0

static func _fill_square(out: Image, color: Color) -> void:
	var n := out.get_width()
	for y in n:
		for x in n:
			out.set_pixel(x, y, color)

## Alpha-over, in `color`. The parts are white masks, so the colour is the
## recipe's rather than the file's -- one `body_skinny` serves a green goblin
## and a robed priest.
static func _stamp(out: Image, part: Image, color: Color) -> void:
	if part == null:
		return
	for y in mini(out.get_height(), part.get_height()):
		for x in mini(out.get_width(), part.get_width()):
			var a := part.get_pixel(x, y).a
			if a <= 0.0:
				continue
			var src := Color(color.r, color.g, color.b, a)
			out.set_pixel(x, y, out.get_pixel(x, y).blend(src))

## A one-pixel dark border around the composed silhouette. Around the OUTSIDE,
## never between two parts: an outline on every seam turns a body into a
## diagram, and the sprites this replaces outline the creature and not its arms.
## The ring just outside a part, `width` pixels thick. Cached per (part, width):
## a dilation is the most expensive thing in this file and a part is named by
## every recipe that uses it, on both teams.
static var _rings := {}

static func part_ring(part: StringName, width: int) -> Image:
	var key := "%s|%d" % [part, width]
	if _rings.has(key):
		return _rings[key]
	var src := part_image(part)
	var ring: Image = null
	if src != null:
		ring = Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
		ring.fill(Color(0, 0, 0, 0))
		var grown := src.duplicate()
		for _pass in maxi(1, width):
			var edge: Array = []
			for y in grown.get_height():
				for x in grown.get_width():
					if grown.get_pixel(x, y).a <= 0.0 and _touches_ink(grown, x, y):
						edge.append(Vector2i(x, y))
			for p: Vector2i in edge:
				grown.set_pixel(p.x, p.y, Color.WHITE)
				ring.set_pixel(p.x, p.y, Color.WHITE)
	_rings[key] = ring
	return ring

static func _touches_ink(img: Image, x: int, y: int) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q := Vector2i(x, y) + d
		if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
			continue
		if img.get_pixel(q.x, q.y).a > 0.0:
			return true
	return false
