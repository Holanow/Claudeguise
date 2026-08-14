extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")
const UIArt := preload("res://Scripts/Art/UIArt.gd")
const ActionIcons := preload("res://Scripts/Art/ActionIcons.gd")
## Only for `draw_item_by_id`, which is a convenience for a caller holding an id
## rather than a def. No cycle: nothing under `Scripts/Content` reaches into
## `Scripts/Art`.
const Registry := preload("res://Scripts/Content/Registry.gd")

## One icon per item, for issue #100's equip screen.
##
## Seventeen items have existed in `Scripts/Content/Modules/core_items.gd` since
## issue 39 and none of them has ever had any visual identity at all. The equip
## screen is being built now, so this goes in front of it rather than behind it.
##
## MANAGER-OWNED (`Scripts/Art/**`). Nothing here draws itself into a screen:
## placement is `Scripts/UI`, wren's. See TEAM_LOG.md, sable's block, for the
## call signature.
##
## ---------------------------------------------------------------------------
## THE RULES
##
## 1. THE PLATE IS THE SLOT, AND IT IS TWO CHANNELS, NOT ONE. A player has to
##    tell a weapon from an armor from an accessory before they read anything,
##    and the glyph is not what does that -- the same reasoning as the status
##    badges, where plate direction and rim colour carry the harmful/beneficial
##    read and the glyph only disambiguates.
##
##      SHAPE.  Weapon is a DIAMOND, sharp, points at the compass.
##              Armor is a BROAD SLAB, wide and flat-topped with clipped bottom
##              corners, heavier than it is tall.
##              Accessory is a CIRCLE, small and round with no corners at all.
##      COLOUR. Weapon warm, armor cool, accessory neutral.
##
##    Sharp versus broad versus round survives when nothing inside the plate
##    does, and it works for a player who cannot separate the rim colours.
##
## 2. NONE OF THE THREE PLATES IS ANOTHER SYSTEM'S PLATE. `StatusIcons` owns the
##    up-and-down wedges and `ActionIcons` owns the clipped-corner square. Three
##    icon systems can appear on one screen -- the equip screen shows an item,
##    its granted action, and the status that action applies -- and a glance
##    should never have to work out which system it is reading first. That is
##    also why the accessory plate is a true circle rather than an octagon: an
##    octagon is what `ActionIcons.PLATE` already is.
##
## 3. AN ITEM THAT GRANTS AN ACTION SAYS SO, AND SAYS WHICH. `plate_mail`
##    teaches Directional Block. An item that changes what a pawn *can do* is a
##    different kind of thing from one that adds 3 STR, and until now nothing on
##    screen distinguished them. Such an item carries a CORNER BADGE holding the
##    granted action's own glyph -- the same shape `ActionIcons` draws on the
##    wind-up bar and, for `warrior_block`, the same shape `StatusIcons` draws
##    when the block lands. One glyph learned, three places it means the same
##    thing.
##
##    Two channels again: the badge is on its own disc, a shape no plain-stats
##    item has, so "this item grants something" reads before the badge glyph
##    itself is legible.
##
## 4. SILHOUETTE OVER DETAIL, and no two glyphs share an outline. Same finding
##    as the unit roster and the ability icons. These are designed at 32px and
##    checked at 20px, and `Tools/EquipmentIconSheet.tscn` renders every one of
##    them together at true size, because six collisions on the ability sheet
##    survived a table that read correctly and two more survived the pass after
##    that.
##
## ---------------------------------------------------------------------------
## THE FOUR RINGS, WHICH ARE THE HARD CASE AND ARE HANDLED DELIBERATELY
##
## Four of the eight accessories are `brown_ring`, `red_ring`, `blue_ring` and
## `yellow_ring`. They are four rings; pretending they have four different
## outlines would be inventing a difference the content does not have, which is
## the mistake rule 4 exists to prevent in the other direction.
##
## So they share a band and differ on two channels of their own:
##
##   GEM COLOUR, which is the item's own name and therefore the one thing a
##   player already knows about it before looking.
##   GEM CUT, so the four are still separable in greyscale: square, rhombus,
##   round and triangular.
##
## The colours are DERIVED from existing `Palette` tokens rather than written as
## literals, because every colour in this project belongs in `Palette` and
## `Palette` is not my file. Deriving costs nothing and needs nobody.

## Rim colours per slot. Derived from tokens, and deliberately not `HP_LOW` /
## `HP_FULL`, which `StatusIcons` has already spent on harmful-versus-beneficial
## -- a red-rimmed item next to a red-rimmed status badge would be two systems
## using one channel for two meanings.
static func slot_color(slot: EquipmentDef.Slot) -> Color:
	match slot:
		EquipmentDef.Slot.WEAPON:
			return Palette.RESOURCE_RAGE
		EquipmentDef.Slot.ARMOR:
			return Palette.TEAM_PLAYER
		_:
			return Palette.TEXT_DIM

## Sharp. A diamond has a point in all four directions and nothing else on any
## of the three icon systems does.
const PLATE_WEAPON := [[0.0, -1.0], [1.0, 0.0], [0.0, 1.0], [-1.0, 0.0]]

## Broad and heavy. Flat across the top, clipped at the bottom corners so it sits
## rather than floats, and wider than it is tall -- which is the difference
## between reading as armor and reading as a plain box.
const PLATE_ARMOR := [
	[-1.0, -0.62], [1.0, -0.62], [1.0, 0.34], [0.66, 0.72],
	[-0.66, 0.72], [-1.0, 0.34],
]

## Round. Drawn as a circle rather than a polygon on purpose -- see rule 2, an
## n-gon here would be `ActionIcons.PLATE` with more sides.
const PLATE_ACCESSORY_RADIUS := 1.0

## The fraction of the plate a glyph is allowed to use, PER SLOT, because the
## three plates do not have remotely the same usable area and one number for all
## three starves two of them.
##
## The diamond is the tight one and it is tight for a reason that is arithmetic
## rather than taste: the largest axis-aligned square inside `|x| + |y| <= 1` has
## a half-side of 0.5, so a weapon glyph can never exceed half the plate. The
## slab and the circle have no such limit and were drawn at the diamond's budget
## in the first pass, which is why `scrubs` and `censer` came out as specks.
const _GLYPH_INSET := {
	EquipmentDef.Slot.WEAPON: 0.27,
	EquipmentDef.Slot.ARMOR: 0.22,
	EquipmentDef.Slot.ACCESSORY: 0.20,
}

## ---------------------------------------------------------------------------
## GLYPHS. `UIArt.draw_glyph`'s -1..1 part format, same as `StatusIcons` and
## `ActionIcons`, so the three files read alike.

## Weapons ------------------------------------------------------------------

## Deliberately the same shape family as `ActionIcons._SWORD`, tilted for the
## same reason: drawn upright, a blade and a crossguard of similar weight is a
## plus sign. It looks like the Warrior's Strike icon because it is the object
## that icon depicts, and an item that looks like the thing it does is not a
## collision. Nothing else in the item set is cross-shaped.
const _SWORD := [
	{"poly": [[0.0, -0.94], [0.18, -0.58], [0.18, 0.2], [-0.18, 0.2], [-0.18, -0.58]], "rot": 0.55},
	{"poly": [[-0.46, 0.2], [0.46, 0.2], [0.4, 0.38], [-0.4, 0.38]], "rot": 0.55},
	{"poly": [[-0.09, 0.38], [0.09, 0.38], [0.09, 0.78], [-0.09, 0.78]], "rot": 0.55},
	{"dot": [0.0, 0.85, 0.13], "rot": 0.55},
]

## An open-ended wrench: a C-jaw at the head and a closed ring at the tail. The
## ring is what stops it reading as a hammer, which is the nearest neighbour on
## any sheet these two ever share.
## A rotated part has to stay inside the unit CIRCLE, not just the unit square,
## or it leaves the icon's box at some angles -- the same trap `ActionIcons._AXE`
## documents. The first jaw here reached 1.01 and would have clipped.
const _WRENCH := [
	{"poly": [[-0.18, 0.36], [0.18, 0.36], [0.18, -0.3], [-0.18, -0.3]], "rot": -0.5},
	{"poly": [
		[-0.5, -0.26], [-0.5, -0.82], [-0.22, -0.82], [-0.22, -0.54],
		[0.22, -0.54], [0.22, -0.82], [0.5, -0.82], [0.5, -0.26],
	], "rot": -0.5},
	{"arc": [0.0, 0.56, 0.26], "w": 0.24, "rot": -0.5},
]

## A deep crescent opening left, on a handle running down to the right. FILLED,
## not a stroked arc: a stroked arc plus a line is `ActionIcons._HOOK` exactly.
##
## The first version stood the handle upright with the crescent balanced on top
## of it, and it rendered as **an upward arrow** -- a mass on a vertical stick is
## an arrowhead, whatever the mass is shaped like. The diagonal is what fixes it,
## the same thirty-degrees-destroys-the-read finding as `_SWORD` and `_DAGGER`.
##
## Three versions died here, all to the same cause: **a crescent that is
## symmetric about the vertical is not a blade, it is an arch.** Upright with the
## handle under it, it was an arrow. Thinned and laid flat, a moustache. Thickened
## and centred, a rainbow. A blade has a root and a tip and they are not the same
## end, so this one is a J -- a handle running down to the lower left and a hook
## that curls up and to the right and comes back down to a point.
const _SICKLE := [
	{"poly": [[-0.72, 0.86], [-0.44, 0.96], [0.06, -0.16], [-0.22, -0.28]]},
	{"poly": [
		[-0.24, -0.28], [0.2, -0.72], [0.72, -0.72], [0.94, -0.3],
		[0.6, -0.22], [0.44, -0.46], [0.14, -0.4], [-0.02, -0.12],
	]},
]

## A sphere on a plinth. `ActionIcons._ORB` is a sphere with a tail -- a bolt in
## flight. This one is the object standing on something.
##
## The first version cradled it in two angled prongs and rendered as **a figure
## with a head and a body**: two symmetrical diagonals under a circle is a torso,
## and that is what the eye reaches for first. A single flat plinth cannot be a
## body.
##
## The second version kept a tapered neck between the sphere and the base and
## rendered as **a chess pawn**. There is no neck now: a sphere resting on a bar,
## with air between them, cannot be a body and a head.
const _ORB := [
	{"dot": [0.0, -0.28, 0.64]},
	{"poly": [[-0.8, 0.58], [0.8, 0.58], [0.8, 0.94], [-0.8, 0.94]]},
]

## Armor --------------------------------------------------------------------
##
## Three of the five armors are garments and that is the real hazard in this set,
## not the weapons. Robes, a Gown and Scrubs authored carelessly are one shape
## three times. They are separated on structure, which survives the size:
##
##   robes   -- HOODED, closed, falling straight. A cowl point above the
##              shoulders and a hem no wider than the body.
##   gown    -- NO HOOD, cinched waist, a wide bell skirt. An hourglass, and the
##              only silhouette here that is narrower in the middle than at
##              either end.
##   scrubs  -- SHORT, and it has LEGS. A V-necked top ending above the waist
##              with two separate trouser legs under it, so the outline is
##              broken by a gap no full-length garment has.

## A cuirass. Flared shoulders, a waist, and a centre seam.
const _CUIRASS := [
	{"poly": [
		[-0.9, -0.5], [-0.42, -0.82], [-0.2, -0.62], [0.2, -0.62], [0.42, -0.82],
		[0.9, -0.5], [0.62, -0.04], [0.5, 0.84], [-0.5, 0.84], [-0.62, -0.04],
	]},
	{"line": [[0.0, -0.5], [0.0, 0.76]], "w": 0.12},
]

## A strap wound on the diagonal, with a knot in the middle and one loose end.
##
## Three versions died here and every death was a different kind of failure,
## which is why they are all written down:
##
##   SHAPE. Three staggered horizontal bands rendered as an **equals sign** --
##   the third time this project has learned that parallel bars of similar length
##   collapse into one, after `StatusIcons.BLOCK` and the note in its own
##   comment. Staggering the ends does not save it: at 20px an end is one pixel
##   and the parallelism is the whole shape.
##
##   CONVENTION. Crossing them into an X fixed the shape and broke the meaning:
##   **an X on a dark plate in a menu reads as "remove this"**, and this icon
##   will spend its whole life on an equip screen beside a control that does
##   exactly that. A shape collision is a confusion; a convention collision is a
##   misclick.
##
##   OBJECT. A coil with a tail leaving it rendered as **a magnifying glass**.
##   Two concentric circles are a lens, whatever you meant by them.
##
## A knot is none of those things, and it is the thing the item is.
const _WRAPS := [
	{"poly": [[-0.2, -0.96], [0.2, -0.96], [0.2, 0.96], [-0.2, 0.96]], "rot": 0.9},
	{"poly": [[-0.5, -0.3], [0.5, -0.3], [0.5, 0.3], [-0.5, 0.3]], "rot": 0.9},
	{"poly": [[0.2, 0.3], [0.72, 0.62], [0.5, 0.92], [0.2, 0.72]], "rot": 0.9},
]

## Hooded, closed, straight. The cowl is a point that rises clear of the
## shoulders, which nothing else in the set has.
const _ROBE := [
	{"poly": [
		[0.0, -0.94], [0.38, -0.5], [0.62, -0.32], [0.5, 0.86], [-0.5, 0.86],
		[-0.62, -0.32], [-0.38, -0.5],
	]},
	{"poly": [[-0.24, -0.72], [0.24, -0.72], [0.16, -0.34], [-0.16, -0.34]]},
]

## An hourglass: shoulders, a pinched waist, a bell that is the widest thing on
## the sheet. No hood, and the neckline is a straight bar.
const _GOWN := [
	{"poly": [
		[-0.44, -0.86], [0.44, -0.86], [0.28, -0.5], [0.16, -0.12],
		[0.9, 0.86], [-0.9, 0.86], [-0.16, -0.12], [-0.28, -0.5],
	]},
]

## Short, deeply V-necked, with sleeves that stick out and two legs under it.
##
## The first version had a shallow neck and no sleeves and rendered as **a box
## with two teeth**. The sleeves are what make the top half a garment rather than
## a container, and the V has to be deep enough to survive: a shallow notch at
## 20px is one pixel of missing edge.
const _SCRUBS := [
	{"poly": [
		[-0.6, -0.92], [-0.24, -0.92], [0.0, -0.44], [0.24, -0.92], [0.6, -0.92],
		[0.96, -0.66], [0.72, -0.3], [0.56, -0.42], [0.56, 0.06], [-0.56, 0.06],
		[-0.56, -0.42], [-0.72, -0.3], [-0.96, -0.66],
	]},
	{"poly": [[-0.54, 0.2], [-0.1, 0.2], [-0.1, 0.94], [-0.54, 0.94]]},
	{"poly": [[0.1, 0.2], [0.54, 0.2], [0.54, 0.94], [0.1, 0.94]]},
]

## Accessories --------------------------------------------------------------

## A tapered honing stone held on the diagonal, with a chipped corner. Angled so
## it is not a plain rectangle, which is the only shape a small dark plate can be
## confused with.
const _WHETSTONE := [
	{"poly": [
		[-0.88, 0.34], [-0.5, -0.02], [0.42, -0.88], [0.86, -0.5],
		[0.5, -0.1], [0.16, 0.16], [-0.5, 0.86],
	]},
	{"line": [[-0.62, 0.5], [0.3, -0.44]], "w": 0.1},
]

## A censer on two chains, lid and bowl, hanging. Told apart from
## `ActionIcons._CHAIN` -- one line and one dot -- by having a bowl, a lid and a
## suspension ring rather than a ball on a string.
## The suspension ring is gone and the bowl is much heavier than the first pass,
## which drew a thin flask on two hairlines and read as a bottle. What survives at
## 20px is the wide lid over a deep bowl; the chains only have to be present.
const _CENSER := [
	{"line": [[-0.1, -0.94], [-0.6, -0.36]], "w": 0.12},
	{"line": [[0.1, -0.94], [0.6, -0.36]], "w": 0.12},
	{"poly": [[-0.78, -0.34], [0.78, -0.34], [0.6, -0.06], [-0.6, -0.06]]},
	{"poly": [[-0.66, 0.02], [0.66, 0.02], [0.4, 0.92], [-0.4, 0.92]]},
]

## A bound totem: a head, out-flung arms and a tapered post. Deliberately
## figure-shaped, which is the one read nothing else in this set has -- and the
## read `ActionIcons._BEAM` had to be redrawn to lose.
const _FETISH := [
	{"dot": [0.0, -0.6, 0.34]},
	{"poly": [[-0.9, -0.32], [0.9, -0.32], [0.9, -0.06], [-0.9, -0.06]]},
	{"poly": [[-0.34, -0.14], [0.34, -0.14], [0.18, 0.9], [-0.18, 0.9]]},
	{"line": [[-0.34, 0.28], [0.34, 0.28]], "w": 0.14},
]

## Four corner brackets around an empty middle. The item is called Piece of
## Nothing; an absence is what it is, and a shape with a hole where its subject
## should be is the only glyph on the sheet that is mostly not there.
const _NOTHING := [
	{"line": [[-0.86, -0.42], [-0.86, -0.86], [-0.42, -0.86]], "w": 0.16},
	{"line": [[0.42, -0.86], [0.86, -0.86], [0.86, -0.42]], "w": 0.16},
	{"line": [[0.86, 0.42], [0.86, 0.86], [0.42, 0.86]], "w": 0.16},
	{"line": [[-0.42, 0.86], [-0.86, 0.86], [-0.86, 0.42]], "w": 0.16},
]

## The shared ring band. Thinner and lower than the first pass, so the gem can
## be big enough for its cut to survive -- on the first sheet the band was heavy,
## the gem was a speck, and all four rings were one icon in four colours.
const _RING_BAND := [
	{"arc": [0.0, 0.34, 0.56], "w": 0.2},
]

## The four gem cuts. Shape is the channel that survives greyscale; `gem_color`
## is the channel that survives distance.
##
## **Stated as a limit rather than hidden:** at 20px the cut is two or three
## pixels and the four rings separate by COLOUR ALONE. That is a real weakness
## and it is the reason these are drawn as large as the band allows. At 32px, the
## equip screen's own size, the cuts do separate -- checked on the sheet, not
## reasoned about.
const _GEM_SQUARE := [{"poly": [[-0.46, -0.94], [0.46, -0.94], [0.46, -0.14], [-0.46, -0.14]]}]
const _GEM_RHOMBUS := [{"poly": [[0.0, -1.0], [0.56, -0.54], [0.0, -0.08], [-0.56, -0.54]]}]
const _GEM_ROUND := [{"dot": [0.0, -0.54, 0.48]}]
const _GEM_TRIANGLE := [{"poly": [[0.0, -1.0], [0.6, -0.1], [-0.6, -0.1]]}]

## Every item id in the content registry. `Tests/test_art.gd` asserts this covers
## `Registry.all_equipment_ids()` exactly, so an item added in `Scripts/Content`
## fails the gate here rather than shipping with no icon -- which is how
## `EquipmentDef` itself sat unreachable for weeks.
const GLYPHS := {
	# Weapons.
	&"sword": _SWORD,
	&"wrench": _WRENCH,
	&"sickle": _SICKLE,
	&"orb": _ORB,

	# Armor.
	&"plate_mail": _CUIRASS,
	&"silk_wraps": _WRAPS,
	&"robes": _ROBE,
	&"gown": _GOWN,
	&"scrubs": _SCRUBS,

	# Accessories. The four rings share `_RING_BAND` and differ by gem; see the
	# header. Their entries are assembled in `glyph_for`, because a const cannot
	# concatenate another const at parse time.
	&"whetstone": _WHETSTONE,
	&"censer": _CENSER,
	&"fetish": _FETISH,
	&"piece_of_nothing": _NOTHING,
}

## The rings, id to gem parts. Kept apart from `GLYPHS` so the "no two share an
## outline" test can treat them as one deliberate family rather than four
## accidents.
const RING_GEMS := {
	&"brown_ring": _GEM_SQUARE,
	&"red_ring": _GEM_RHOMBUS,
	&"blue_ring": _GEM_ROUND,
	&"yellow_ring": _GEM_TRIANGLE,
}

## Drawn when an id has no entry. Same reasoning as `ActionIcons._UNKNOWN`: a
## missing icon must look like a missing icon, not like a blank panel.
const _UNKNOWN := [
	{"arc": [0.0, 0.0, 0.6], "w": 0.2},
	{"dot": [0.0, 0.55, 0.16]},
]

## The gem colour of each ring, derived from `Palette` rather than written as a
## literal. `Scripts/Core/Palette.gd` owns every colour in this project and it is
## rook's file; deriving from the tokens that are already there gets the four
## named colours without an edit to the skeleton and without a literal here.
##
## Brown is `RESOURCE_RAGE` darkened, because the palette has an orange and no
## brown, and a darkened orange is what brown is. `UnitArt` already establishes
## deriving a shade this way.
static func gem_color(item_id: StringName) -> Color:
	match item_id:
		&"brown_ring":
			return Palette.RESOURCE_RAGE.darkened(0.3)
		&"red_ring":
			return Palette.HP_LOW
		&"blue_ring":
			return Palette.RESOURCE_MANA
		&"yellow_ring":
			return Palette.RESOURCE_ENERGY
		_:
			return Palette.TEXT

## The parts for one item.
static func glyph_for(item_id: StringName) -> Array:
	if RING_GEMS.has(item_id):
		return _RING_BAND + RING_GEMS[item_id]
	return GLYPHS.get(item_id, _UNKNOWN)

static func has_glyph(item_id: StringName) -> bool:
	return GLYPHS.has(item_id) or RING_GEMS.has(item_id)

## Every id this file draws, so a test can compare it against the registry.
static func known_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in GLYPHS.keys():
		out.append(k)
	for k in RING_GEMS.keys():
		out.append(k)
	return out

## The override a dropped-in PNG lives under: `Assets/UI/item/plate_mail.png`.
## The item id, unchanged, for the same guessability as `Assets/Units/warrior.png`
## and `Assets/UI/action/warrior_execute.png`.
static func art_name(item_id: StringName) -> StringName:
	return StringName("item/%s" % item_id)

## The plate polygon for a slot, or an empty array for the accessory circle,
## which is not a polygon. Split out so a test can check the plates without a
## live canvas, the same reason `Silhouettes.build_parts` is split from its draw.
static func plate_points(slot: EquipmentDef.Slot) -> Array:
	match slot:
		EquipmentDef.Slot.WEAPON:
			return PLATE_WEAPON
		EquipmentDef.Slot.ARMOR:
			return PLATE_ARMOR
		_:
			return []

## One item icon filling `rect`. Designed at 32px; checked at 20px and 48px.
##
## Draws a dropped-in PNG if one exists and the generated icon otherwise. The
## caller never asks which.
static func draw_item(canvas: CanvasItem, item: EquipmentDef, rect: Rect2) -> void:
	if item == null:
		return
	var tex := UIArt.texture_for(art_name(item.id))
	if tex != null:
		UIArt.draw_fit(canvas, tex, rect)
		return
	_draw_plate(canvas, item.slot, rect, slot_color(item.slot))
	var color := gem_color(item.id) if RING_GEMS.has(item.id) else Palette.TEXT
	UIArt.draw_glyph(canvas, glyph_for(item.id), _inner(item.slot, rect), color)
	if not item.granted_actions.is_empty():
		_draw_grant_badge(canvas, item.granted_actions[0], rect)

## The same thing when the caller has an id rather than a def. Deliberately a
## second function and not a default argument: the equip screen has the def in
## hand and should not pay a registry lookup per icon per frame.
static func draw_item_by_id(canvas: CanvasItem, item_id: StringName, rect: Rect2) -> void:
	draw_item(canvas, Registry.get_equipment(item_id), rect)

## An unfilled slot: the plate, dimmed, with no glyph. So an empty weapon slot
## still reads as a weapon slot rather than as a hole in the layout -- the equip
## screen shows three per pawn and most of them are empty most of the time.
static func draw_empty_slot(canvas: CanvasItem, slot: EquipmentDef.Slot, rect: Rect2) -> void:
	var dim := slot_color(slot)
	dim.a = 0.45
	_draw_plate(canvas, slot, rect, dim)

## Where the glyph goes inside the plate.
static func _inner(slot: EquipmentDef.Slot, rect: Rect2) -> Rect2:
	var inset: float = _GLYPH_INSET[slot]
	return Rect2(rect.position + rect.size * inset, rect.size * (1.0 - inset * 2.0))

static func _draw_plate(canvas: CanvasItem, slot: EquipmentDef.Slot, rect: Rect2, rim: Color) -> void:
	var half := minf(rect.size.x, rect.size.y) * 0.5
	var width := maxf(1.0, half * 0.13)
	if slot == EquipmentDef.Slot.ACCESSORY:
		# A circle, not an n-gon. See rule 2 -- an octagon here is
		# `ActionIcons.PLATE` with the corners rounded off.
		var r := half * PLATE_ACCESSORY_RADIUS - width * 0.5
		canvas.draw_circle(rect.get_center(), r, Palette.HP_BACK)
		canvas.draw_arc(rect.get_center(), r, 0.0, TAU, 32, rim, width, true)
		return
	UIArt.draw_outlined_polygon(
		canvas, UIArt.glyph_points({"poly": plate_points(slot)}, rect),
		Palette.HP_BACK, rim, width)

## Rule 3. The granted action's own glyph, on its own disc, in the bottom-right
## corner. `ActionIcons.glyph_for` is the source, so this can never drift from
## what the wind-up bar draws for the same action -- there is no second table
## here to disagree with it.
##
## `Palette.TEXT` and not the action's damage colour, deliberately. On the
## ability icons colour means damage type; here it would be a fourth colour
## meaning on a plate whose rim already means slot, and Directional Block has no
## damage type worth naming anyway.
static func _draw_grant_badge(canvas: CanvasItem, action_id: StringName, rect: Rect2) -> void:
	var half := minf(rect.size.x, rect.size.y) * 0.5
	# 0.58 + 0.38 = 0.96, so the badge stays inside the icon's own rect. A badge
	# bleeding into the next slot reads as a rendering bug, not as art.
	var r := half * 0.38
	var center := rect.get_center() + Vector2(half * 0.58, half * 0.58)
	canvas.draw_circle(center, r, Palette.HP_BACK)
	canvas.draw_arc(center, r, 0.0, TAU, 24, Palette.TEXT, maxf(1.0, r * 0.18), true)
	var inner := Rect2(center - Vector2(r, r) * 0.62, Vector2(r, r) * 1.24)
	UIArt.draw_glyph(canvas, ActionIcons.glyph_for(action_id), inner, Palette.TEXT)
