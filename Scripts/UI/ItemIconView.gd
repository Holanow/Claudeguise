extends Control


## Issue 127: the one node that puts `EquipmentIcons` on a screen.

## The size the icons were designed at, per `EquipmentIcons`' own header.
const ICON_SIZE := 32.0

var item: EquipmentDef = null:
	set(value):
		item = value
		queue_redraw()

## Which plate to draw when `item` is null. `EquipmentDef.Slot`, kept untyped
## for the same reason the rest of this screen keeps slots untyped: the enum
## lives on a preloaded const rather than a `class_name`.
var slot: int = EquipmentDef.Slot.WEAPON:
	set(value):
		slot = value
		queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	# The icon is decoration beside a picker that already carries the item's
	# name; it must not sit between the pointer and anything. IGNORE rather than
	# a default, because `Control`'s default is STOP and this node covers part of
	# a row a player reaches into.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var box := Rect2(Vector2.ZERO, Vector2(ICON_SIZE, ICON_SIZE))
	if item == null:
		EquipmentIcons.draw_empty_slot(self, slot, box)
	else:
		EquipmentIcons.draw_item(self, item, box)
