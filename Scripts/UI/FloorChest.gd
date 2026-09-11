extends Node2D
class_name FloorChest

## Issue 919: the reward of a cleared room, drawn in the room and clicked, the
## same gesture in the same place as #805's doors. The player: "Loot should come
## from a chest at the end of the room the player clicks on."

## The drawn side of the chest, in arena units. The same comfortable click
## target `FloorDoors.DOOR_SIZE` is, because it is the same gesture.
const CHEST_SIZE := 110.0

var open_for_business: bool = false

func show_chest() -> void:
	open_for_business = true
	visible = true
	queue_redraw()

func clear_chest() -> void:
	open_for_business = false
	visible = false
	queue_redraw()

## The middle of the room. A door sits on the edge it leaves through, so the
## centre is the one place a chest can never be mistaken for one.
static func rect() -> Rect2:
	return Rect2(Vector2.ONE * -CHEST_SIZE * 0.5, Vector2.ONE * CHEST_SIZE)

func has_point(point: Vector2) -> bool:
	return open_for_business and visible and rect().has_point(point)

func _draw() -> void:
	if not open_for_business:
		return
	var tex := UIArt.texture_for(&"room/chest")
	if tex == null:
		draw_rect(rect(), Color.BLACK)
		return
	UIArt.draw_fit(self, tex, rect())
