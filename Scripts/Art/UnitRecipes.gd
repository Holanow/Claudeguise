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
	# --- the goblin family -------------------------------------------------
	# The player: "goblin archer should be the goblin base with a hat on
	# basically". So the archer IS the goblin's recipe with one part added, and
	# that is this issue's whole thesis in one entry: a variant costs a part
	# rather than a drawing.
	&"goblin": [
		{"part": &"body_skinny", "color": "5d7a3a"},
		{"part": &"hands", "color": "7fa050"},
		{"part": &"head_round", "color": "7fa050"},
		{"part": &"ears_pointed", "color": "6f8f4a"},
		{"part": &"nose_triangle", "color": "8fb45c"},
		{"part": &"eyes", "color": "1c1a12"},
	],
	&"goblin_archer": {"base": &"goblin", "add": [
		{"part": &"hat", "color": "3b5a44"},
	]},

	# --- the dungeon family, and the same saving found twice ---------------
	# `dungeon_grunt`, `_archer` and `_cultist` were three drawings of one
	# soldier. They are now one base and one hat each.
	&"dungeon_grunt": [
		{"part": &"body_muscular", "team": true},
		{"part": &"hands_wide", "color": "d8b48c"},
		{"part": &"head_round", "color": "d8b48c"},
		{"part": &"eyes", "color": "1c1a12"},
	],
	&"dungeon_archer": {"base": &"dungeon_grunt", "add": [
		{"part": &"hood", "color": "5a6a4a"},
	]},
	&"dungeon_cultist": {"base": &"dungeon_grunt", "add": [
		{"part": &"hood", "color": "6b3f7a"},
	]},

	# --- the rat family ----------------------------------------------------
	# No ears, twice over: `test_art.gd` caught round ears making the rat as tall
	# as it is wide, and the player has since ruled that nothing but the goblin
	# gets them at all.
	&"rat": [
		{"part": &"body_low", "color": "7a6a58"},
		{"part": &"tail", "color": "8a7a68"},
		{"part": &"head_snouted", "color": "8a7a68"},
		{"part": &"eyes_snout", "color": "c04a4a"},
	],
	# The Rat King is the rat wearing what its name says. `test_art.gd` asserts
	# its back is three crests and not a dome, so the crown is the COLOUR of the
	# three spikes rather than an object anywhere. Three attempts at an object
	# scored 2, 5 and 1 crests -- over the spine, on the head, and inside the
	# middle spike, where its own outline bridged the valleys either side. The
	# test named that last cause in its own failure message.
	&"rat_king": {"base": &"rat", "add": [
		{"part": &"spikes", "color": "e8c84a"},
	]},

	# --- the siege pair ----------------------------------------------------
	&"siege_engine": [
		{"part": &"body_rotund", "team": true},
		{"part": &"wheels", "color": "4a3f36"},
		{"part": &"barrel", "color": "8a8f96"},
	],
	&"siege_master": [
		{"part": &"body_muscular", "team": true},
		{"part": &"hands_wide", "color": "d8b48c"},
		{"part": &"head_round", "color": "d8b48c"},
		{"part": &"helm", "color": "8a8f96"},
		{"part": &"eyes", "color": "1c1a12"},
	],

	# --- the party ---------------------------------------------------------
	&"warrior": [
		{"part": &"body_muscular", "team": true},
		{"part": &"hands_wide", "color": "d8b48c"},
		{"part": &"head_round", "color": "d8b48c"},
		{"part": &"plume", "color": "b8503c"},
		{"part": &"eyes", "color": "1c1a12"},
	],
	&"priest": [
		{"part": &"body_skinny", "team": true},
		{"part": &"hands", "color": "e0c0a0"},
		{"part": &"head_round", "color": "e0c0a0"},
		{"part": &"hood", "color": "e8dcb0"},
		{"part": &"eyes", "color": "1c1a12"},
	],
	&"geysermancer": [
		{"part": &"body_skinny", "team": true},
		{"part": &"hands", "color": "cfe6ee"},
		{"part": &"head_round", "color": "cfe6ee"},
		{"part": &"hat", "color": "3f7fa8"},
		{"part": &"eyes", "color": "1c2a32"},
	],
	&"abomination": [
		{"part": &"body_rotund", "color": "6b4a7a"},
		{"part": &"hands_wide", "color": "7c5a8c"},
		{"part": &"head_small", "color": "7c5a8c"},
		{"part": &"horns", "color": "d8cbe0"},
		{"part": &"tusks", "color": "d8cbe0"},
		{"part": &"eyes", "color": "e8d24a"},
	],

	# --- the rest of floor one --------------------------------------------
	&"brute": [
		{"part": &"body_muscular", "color": "8a6a3a"},
		{"part": &"hands_wide", "color": "a08050"},
		{"part": &"head_small", "color": "a08050"},
		{"part": &"horns", "color": "e0d4b8"},
		{"part": &"eyes", "color": "2a1c10"},
	],
	&"cultist": [
		{"part": &"body_skinny", "color": "4a2f5a"},
		{"part": &"hands", "color": "c8a0b8"},
		{"part": &"head_round", "color": "c8a0b8"},
		{"part": &"hood", "color": "6b3f7a"},
		{"part": &"eyes", "color": "e8d24a"},
	],
	&"ghoul": [
		{"part": &"body_skinny", "color": "6a7a68"},
		{"part": &"hands", "color": "8a9a88"},
		{"part": &"head_small", "color": "8a9a88"},
		{"part": &"tusks", "color": "d8dcd0"},
		{"part": &"eyes", "color": "c04a4a"},
	],
	&"grub": [
		{"part": &"body_rotund", "color": "9a8a5a"},
		{"part": &"head_small", "color": "b0a070"},
		{"part": &"mandibles", "color": "5a4a2a"},
		{"part": &"eyes", "color": "2a2010"},
	],
	&"stalker": [
		{"part": &"body_skinny", "color": "3a3a4a"},
		{"part": &"tail", "color": "4a4a5a"},
		{"part": &"hands", "color": "4a4a5a"},
		{"part": &"head_small", "color": "4a4a5a"},
		{"part": &"eyes", "color": "e8d24a"},
	],
	&"the_warden": [
		{"part": &"body_muscular", "color": "8a4a3a"},
		{"part": &"hands_wide", "color": "a05a48"},
		{"part": &"head_round", "color": "a05a48"},
		{"part": &"helm", "color": "8a8f96"},
		{"part": &"eyes", "color": "e8d24a"},
	],
}

## A recipe is either a stack of layers or `{"base": id, "add": [...]}`. The
## second form is what makes a variant cost a part: `goblin_archer` is the
## goblin plus a hat, and there is no second copy of the goblin to keep in step.
static func layers_for(shape_id: StringName) -> Array:
	var entry = RECIPES.get(shape_id)
	if entry == null:
		return []
	if entry is Array:
		return entry
	var base: Array = layers_for(entry.get("base", &""))
	return base + (entry.get("add", []) as Array)

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
	var layers := layers_for(shape_id)
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
