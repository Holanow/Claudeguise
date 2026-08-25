extends "res://Scripts/UI/GlossaryIcon.gd"


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

## Issue 591: the icon is now the row's mouseover, so it takes the pointer
## rather than passing it through. It sits at the start of the row, left of the
## slot name and the picker, so nothing it covers is reached through it.
func _ready() -> void:
	super._ready()
	custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)

func _draw() -> void:
	var box := Rect2(Vector2.ZERO, Vector2(ICON_SIZE, ICON_SIZE))
	if item == null:
		EquipmentIcons.draw_empty_slot(self, slot, box)
	else:
		EquipmentIcons.draw_item(self, item, box)
