extends RefCounted
class_name EquipmentIcons

## Only for `draw_item_by_id`, which is a convenience for a caller holding an id
## rather than a def. No cycle: nothing under `Scripts/Content` reaches into
## `Scripts/Art`.

## One icon per item, for issue #100's equip screen.
##
## MANAGER-OWNED (`Scripts/Art/**`). Placement is `Scripts/UI`.
##
## **The icons are now PNGs in `Assets/UI/item/`.** They were polygons in code,
## baked to files by `Tools/BakeGlyphs.tscn` and the geometry deleted -- player's
## ruling, 2026-08-19: *"we should do basically 0 drawing with code ever"*. The
## pictures did not change; only where they live did.
##
## The bake tool went with the geometry, because it reads the geometry it bakes.
## `git log --diff-filter=D -- Tools/BakeGlyphs.gd` finds it.
##
## Three rules the baked set follows, and a replacement is worth keeping them for.
##
## 1. THE PLATE IS THE SLOT, ON TWO CHANNELS. A weapon sits on a DIAMOND, armor
##    on a BROAD SLAB, an accessory on a CIRCLE; warm, cool and neutral rims say
##    the same thing again. Sharp versus broad versus round survives when nothing
##    inside the plate does, and it works for a player who cannot separate the
##    rims. An empty slot draws the plate alone -- `item/empty_weapon.png`,
##    `empty_armor.png`, `empty_accessory.png` -- so an empty weapon slot still
##    reads as a weapon slot rather than as a hole in the layout.
## 2. NONE OF THE THREE PLATES IS ANOTHER SYSTEM'S PLATE. `StatusIcons` owns the
##    up-and-down wedges, `ActionIcons` the clipped-corner square. All three can
##    appear on one screen and a glance should never have to work out which
##    system it is reading first.
## 3. AN ITEM THAT GRANTS AN ACTION SAYS SO, AND SAYS WHICH -- see
##    `_draw_grant_badge`, which is the one thing here still drawn over the art.
##
## The four rings share a band and differ by gem colour and gem cut, because they
## are four rings and inventing four outlines would be inventing a difference the
## content does not have. That is baked into the four files now.

## Rim colours per slot. Deliberately not `HP_LOW` / `HP_FULL`, which
## `StatusIcons` has already spent on harmful-versus-beneficial.
##
## Still live: `Scripts/UI` tints text and chips per slot from this.
static func slot_color(slot: EquipmentDef.Slot) -> Color:
	match slot:
		EquipmentDef.Slot.WEAPON:
			return Palette.RESOURCE_RAGE
		EquipmentDef.Slot.ARMOR:
			return Palette.TEAM_PLAYER
		_:
			return Palette.TEXT_DIM

## The file this icon is drawn from: `Assets/UI/item/plate_mail.png`. The item
## id, unchanged, for guessability.
static func art_name(item_id: StringName) -> StringName:
	return StringName("item/%s" % item_id)

static func has_glyph(item_id: StringName) -> bool:
	return UIArt.has_art(art_name(item_id))

## The empty plate for a slot: `item/empty_weapon.png` and its two siblings.
static func empty_art_name(slot: EquipmentDef.Slot) -> StringName:
	return StringName("item/empty_%s" % String(EquipmentDef.Slot.keys()[slot]).to_lower())

## One item icon filling `rect`. Designed at 32px; checked at 20px and 48px.
##
## A missing file draws a black square. Player's ruling: *"a missing sprite can
## fall back to a black square"*.
static func draw_item(canvas: CanvasItem, item: EquipmentDef, rect: Rect2) -> void:
	if item == null:
		return
	_draw_art(canvas, art_name(item.id), rect)
	# The badge is drawn OVER the art, and that is deliberate. It was inside the
	# generated branch until the drop-in was rendered end to end, and the render
	# showed the cost: a PNG for `plate_mail` replaced the icon and silently
	# deleted the only thing on screen saying that this item teaches an ability.
	# A picture may replace decoration and may not replace information.
	if not item.granted_actions.is_empty():
		_draw_grant_badge(canvas, item.granted_actions[0], rect)

## The same thing when the caller has an id rather than a def. Deliberately a
## second function and not a default argument: the equip screen has the def in
## hand and should not pay a registry lookup per icon per frame.
static func draw_item_by_id(canvas: CanvasItem, item_id: StringName, rect: Rect2) -> void:
	draw_item(canvas, Registry.get_equipment(item_id), rect)

## An unfilled slot: the plate, dimmed, with no glyph. The equip screen shows
## three per pawn and most of them are empty most of the time.
static func draw_empty_slot(canvas: CanvasItem, slot: EquipmentDef.Slot, rect: Rect2) -> void:
	_draw_art(canvas, empty_art_name(slot), rect)

static func _draw_art(canvas: CanvasItem, name: StringName, rect: Rect2) -> void:
	var tex := UIArt.texture_for(name)
	if tex == null:
		canvas.draw_rect(rect, Color.BLACK)
		return
	UIArt.draw_fit(canvas, tex, rect)

## The granted action's own icon, on its own disc, in the bottom-right corner.
## `ActionIcons` is the source, so this cannot drift from what the wind-up bar
## draws for the same action -- there is no second picture here to disagree.
##
## The disc is drawn rather than baked because it is not art: it is the frame
## that says "this item grants something" before the icon inside it is legible,
## and it has to sit on top of whatever the item's own picture put there.
static func _draw_grant_badge(canvas: CanvasItem, action_id: StringName, rect: Rect2) -> void:
	var half := minf(rect.size.x, rect.size.y) * 0.5
	# 0.58 + 0.38 = 0.96, so the badge stays inside the icon's own rect. A badge
	# bleeding into the next slot reads as a rendering bug, not as art.
	var r := half * 0.38
	var center := rect.get_center() + Vector2(half * 0.58, half * 0.58)
	canvas.draw_circle(center, r, Palette.HP_BACK)
	canvas.draw_arc(center, r, 0.0, TAU, 24, Palette.TEXT, maxf(1.0, r * 0.18), true)
	var tex := UIArt.texture_for(ActionIcons.art_name(action_id))
	if tex != null:
		UIArt.draw_fit(canvas, tex, Rect2(center - Vector2(r, r) * 0.72, Vector2(r, r) * 1.44))
