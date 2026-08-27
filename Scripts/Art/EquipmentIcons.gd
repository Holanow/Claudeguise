extends RefCounted
class_name EquipmentIcons

## Only for `draw_item_by_id`, which is a convenience for a caller holding an id
## rather than a def. No cycle: nothing under `Scripts/Content` reaches into
## `Scripts/Art`.

## One icon per item, for issue #100's equip screen.

## Rim colours per slot. Deliberately not `HP_LOW` / `HP_FULL`, which
## `StatusIcons` has already spent on harmful-versus-beneficial.
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
static func draw_item(canvas: CanvasItem, item: EquipmentDef, rect: Rect2) -> void:
	if item == null:
		return
	_draw_art(canvas, art_name(item.id), rect)
	# The badge is drawn OVER the art, and that is deliberate. It was inside the
	# generated branch until the drop-in was rendered end to end, and the render
	# showed the cost: a PNG for `plate_mail` replaced the icon and silently
	# deleted the only thing on screen saying that this item teaches an ability.
	if not item.granted_actions.is_empty():
		_draw_grant_badge(canvas, item.granted_actions[0], rect)

## The same thing when the caller has an id rather than a def. Deliberately a
## second function and not a default argument: the equip screen has the def in
## hand and should not pay a registry lookup per icon per frame.
static func draw_item_by_id(canvas: CanvasItem, item_id: StringName, rect: Rect2) -> void:
	draw_item(canvas, ItemLibrary.get_equipment(item_id), rect)

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
