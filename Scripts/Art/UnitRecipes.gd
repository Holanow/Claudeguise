extends RefCounted
class_name UnitRecipes


## Issue 566. What a unit is made of, rather than a drawing of it.
##
## A recipe is a stack of parts from `Assets/Units/parts/`, bottom first, each
## with a colour. `slots_for` sorts that stack into the fixed slots `UnitVisual`
## builds its sprite tree from; nothing here composes anything.

## `team` on a layer takes `Palette.team_color` instead of `color`, which is the
## one place a side changes what a unit looks like.
##
## Issue 584: a body used to name one `hands`/`hands_wide` part and get both
## hands as a single sprite that could only move as one. Every recipe below
## names its hand part twice, once per named slot (`HandMain`, `HandOff`), so
## a slash can swing one hand and counterweight the other.
const RECIPES := {
	# --- the goblin family -------------------------------------------------
	# The player: "goblin archer should be the goblin base with a hat on
	# basically". So the archer IS the goblin's recipe with one part added, and
	# that is this issue's whole thesis in one entry: a variant costs a part
	# rather than a drawing.
	&"goblin": [
		{"part": &"body_skinny", "color": "5d7a3a"},
		{"part": &"hand", "color": "7fa050"},
		{"part": &"hand_off", "color": "7fa050"},
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
		{"part": &"hand_wide", "color": "d8b48c"},
		{"part": &"hand_wide_off", "color": "d8b48c"},
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
	# The player, 2026-08-25: "the Rat King's crown should be a hat instead of
	# whatever it is now". So it is the archer's hat in gold, and the crown is a
	# recolour rather than a part of its own -- the fifth reuse of this
	# vocabulary and the cheapest possible variant.
	&"rat_king": {"base": &"rat", "add": [
		{"part": &"hat_low", "color": "e8c84a"},
	]},

	# --- the siege pair ----------------------------------------------------
	&"siege_engine": [
		{"part": &"body_rotund", "team": true},
		{"part": &"wheels", "color": "4a3f36"},
		{"part": &"barrel", "color": "8a8f96"},
	],
	&"siege_master": [
		{"part": &"body_muscular", "team": true},
		{"part": &"hand_wide", "color": "d8b48c"},
		{"part": &"hand_wide_off", "color": "d8b48c"},
		{"part": &"head_round", "color": "d8b48c"},
		{"part": &"helm", "color": "8a8f96"},
		{"part": &"eyes", "color": "1c1a12"},
	],

	# --- the party ---------------------------------------------------------
	&"warrior": [
		{"part": &"body_muscular", "team": true},
		{"part": &"hand_wide", "color": "d8b48c"},
		{"part": &"hand_wide_off", "color": "d8b48c"},
		{"part": &"head_round", "color": "d8b48c"},
		{"part": &"plume", "color": "b8503c"},
		{"part": &"eyes", "color": "1c1a12"},
	],
	&"priest": [
		{"part": &"body_skinny", "team": true},
		{"part": &"hand", "color": "e0c0a0"},
		{"part": &"hand_off", "color": "e0c0a0"},
		{"part": &"head_round", "color": "e0c0a0"},
		{"part": &"hood", "color": "e8dcb0"},
		{"part": &"eyes", "color": "1c1a12"},
	],
	&"geysermancer": [
		{"part": &"body_skinny", "team": true},
		{"part": &"hand", "color": "cfe6ee"},
		{"part": &"hand_off", "color": "cfe6ee"},
		{"part": &"head_round", "color": "cfe6ee"},
		{"part": &"hat", "color": "3f7fa8"},
		{"part": &"eyes", "color": "1c2a32"},
	],
	&"abomination": [
		{"part": &"body_rotund", "color": "6b4a7a"},
		{"part": &"hand_wide", "color": "7c5a8c"},
		{"part": &"hand_wide_off", "color": "7c5a8c"},
		{"part": &"head_small", "color": "7c5a8c"},
		{"part": &"horns", "color": "d8cbe0"},
		{"part": &"tusks", "color": "d8cbe0"},
		{"part": &"eyes", "color": "e8d24a"},
	],

	# --- the rest of floor one --------------------------------------------
	&"brute": [
		{"part": &"body_muscular", "color": "8a6a3a"},
		{"part": &"hand_wide", "color": "a08050"},
		{"part": &"hand_wide_off", "color": "a08050"},
		{"part": &"head_small", "color": "a08050"},
		{"part": &"horns", "color": "e0d4b8"},
		{"part": &"eyes", "color": "2a1c10"},
	],
	## Issue 671: the floor's elite. A professional in real armour, so he reads
	## as harder than the goblins beside him without being louder -- helm and
	## plume rather than horns or a crown, which belong to the bosses.
	&"sellsword": [
		{"part": &"body_muscular", "color": "4a4f5e"},
		{"part": &"hands_wide", "color": "c8a888"},
		{"part": &"head_small", "color": "c8a888"},
		{"part": &"helm", "color": "9aa3b4"},
		{"part": &"plume", "color": "8c3b4a"},
		{"part": &"eyes", "color": "1a1a22"},
	],
	&"cultist": [
		{"part": &"body_skinny", "color": "4a2f5a"},
		{"part": &"hand", "color": "c8a0b8"},
		{"part": &"hand_off", "color": "c8a0b8"},
		{"part": &"head_round", "color": "c8a0b8"},
		{"part": &"hood", "color": "6b3f7a"},
		{"part": &"eyes", "color": "e8d24a"},
	],
	&"ghoul": [
		{"part": &"body_skinny", "color": "6a7a68"},
		{"part": &"hand", "color": "8a9a88"},
		{"part": &"hand_off", "color": "8a9a88"},
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
		{"part": &"hand", "color": "4a4a5a"},
		{"part": &"hand_off", "color": "4a4a5a"},
		{"part": &"head_small", "color": "4a4a5a"},
		{"part": &"eyes", "color": "e8d24a"},
	],
	&"the_warden": [
		{"part": &"body_muscular", "color": "8a4a3a"},
		{"part": &"hand_wide", "color": "a05a48"},
		{"part": &"hand_wide_off", "color": "a05a48"},
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

## The fixed slots a body is built from, in draw order. Tree order in
## `UnitVisual` is this order, so nothing sorts at runtime.
##
## Headwear sits UNDER Face rather than over it, which is a deliberate departure
## from the order the issue named: a hood covers the pixels the eyes are drawn on
## and the stack this replaces always drew the eyes last, so Face-over-Headwear
## takes the eyes off the Priest, the Cultist, both hooded dungeon soldiers, the
## Siege Master and The Warden.
##
## Issue 584: `Hands` split into two named slots, and `Weapon` sits between
## them -- off-hand behind it, main hand in front -- so a weapon reads as
## gripped rather than glued on top of both hands at once.
const SLOTS: Array[StringName] = [
	&"Body", &"Head", &"Headwear", &"Face", &"HandOff", &"Weapon", &"HandMain", &"Extra",
]

## Which slot a part goes in. A part named nowhere here lands in `Extra`, so a
## part added later draws last rather than silently joining a group it was never
## put in.
const SLOT_OF := {
	&"body_skinny": &"Body", &"body_muscular": &"Body",
	&"body_rotund": &"Body", &"body_low": &"Body", &"feet": &"Body",
	&"head_round": &"Head", &"head_small": &"Head",
	&"head_tall": &"Head", &"head_snouted": &"Head",
	&"hat": &"Headwear", &"hat_low": &"Headwear", &"hood": &"Headwear",
	&"helm": &"Headwear", &"plume": &"Headwear", &"crown": &"Headwear",
	&"horns": &"Headwear", &"spikes": &"Headwear",
	&"eyes": &"Face", &"eyes_snout": &"Face",
	&"ears_pointed": &"Face", &"ears_round": &"Face",
	&"nose_triangle": &"Face", &"mandibles": &"Face", &"tusks": &"Face",
	&"hand": &"HandMain", &"hand_wide": &"HandMain",
	&"hand_off": &"HandOff", &"hand_wide_off": &"HandOff",
	&"sword": &"Weapon", &"staff": &"Weapon", &"orb": &"Weapon",
	&"bow": &"Weapon", &"sickle": &"Weapon",
}

static func slot_of(part: StringName) -> StringName:
	return SLOT_OF.get(part, &"Extra")

## The recipe sorted into its slots: one entry per slot in `SLOTS` order, each
## carrying the layers that landed in it in the order the recipe named them.
##
## A slot with nothing in it is kept and is empty, because `UnitVisual` builds
## one node per slot whatever the recipe holds -- "an empty slot is a hidden
## sprite" is what makes a Goblin and a Rat King the same tree.
static func slots_for(shape_id: StringName) -> Array:
	var by_slot := {}
	for slot in SLOTS:
		by_slot[slot] = []
	for layer in layers_for(shape_id):
		by_slot[slot_of(layer["part"])].append(layer)
	var out: Array = []
	for slot in SLOTS:
		out.append({"slot": slot, "layers": by_slot[slot]})
	return out

## Issue 630. Which chunk of a body a slot's parts leave with when the body comes
## apart. Slots are a drawing taxonomy and chunks are a physical one: eyes and a
## hat travel with the head they are worn on, a barrel does not travel with a
## wheel. A slot named nowhere here -- `Extra` -- gives every part its own chunk.
##
## `HandMain` and `HandOff` both map to `hands`: they are no longer adjacent in
## `SLOTS` (the `Weapon` slot sits between them), so without this they would
## fly apart as two separate hand chunks on death rather than the one this
## always was.
const CHUNK_OF_SLOT := {
	&"Body": &"body",
	&"Head": &"head", &"Headwear": &"head", &"Face": &"head",
	&"HandMain": &"hands", &"HandOff": &"hands",
}

## A part in no slot lands in `Extra` and is therefore its own chunk, so a part
## added later flies on its own rather than silently joining the body it was
## drawn over. The `Weapon` slot is not in `CHUNK_OF_SLOT`, so a drawn weapon is
## its own chunk too -- there is no recipe layer for it to travel with, since
## it is added at draw time from the wielder's equipment, not authored here.
static func chunk_of(part: StringName) -> StringName:
	return CHUNK_OF_SLOT.get(slot_of(part), part)

## The recipe cut into the chunks a death throws: runs of ADJACENT layers, in the
## order `slots_for` draws them, that share a chunk. Adjacent rather than
## gathered, so the chunks stack back into the drawn body exactly -- every part
## carries its own outline ring, so a layer pulled back under one it was drawn
## over is visible.
static func chunks_for(shape_id: StringName) -> Array:
	var out: Array = []
	for entry in slots_for(shape_id):
		for layer in entry["layers"]:
			var chunk := chunk_of(layer["part"])
			if not out.is_empty() and out[-1]["chunk"] == chunk:
				out[-1]["layers"].append(layer)
				continue
			out.append({"chunk": chunk, "layers": [layer]})
	return out

## Whether this recipe has anything to animate at all: whether its `HandMain`
## or `HandOff` slot holds a part `PartAnimation` moves.
static func has_animated_part(shape_id: StringName) -> bool:
	for layer in layers_for(shape_id):
		if PartAnimation.animates(layer["part"]):
			return true
	return false

## The colour one layer is drawn in. `team` takes `Palette.team_color` instead of
## `color`, which is the one place a side changes what a unit looks like.
static func layer_color(layer: Dictionary, team: CG.Team) -> Color:
	if layer.get("team", false):
		return Palette.team_color(team)
	return Color(layer.get("color", "ffffff"))

## The tint a weapon part draws in. Parts are white masks with no colour of
## their own; every other part gets its colour from a recipe layer, and a
## weapon has none -- it is added at draw time from the wielder's equipment,
## not authored into any recipe. A part named nowhere here draws steel grey.
const WEAPON_COLOR := {
	&"sword": "c8ccd4", &"staff": "8a6a42", &"orb": "7fd0e0",
	&"bow": "9a7a48", &"sickle": "9aa0a8",
}

static func weapon_color(part: StringName) -> Color:
	return Color(WEAPON_COLOR.get(part, "9aa0a8"))
