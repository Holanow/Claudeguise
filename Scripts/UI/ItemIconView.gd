extends Control

const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")
const EquipmentIcons := preload("res://Scripts/Art/EquipmentIcons.gd")

## Issue 127: the one node that puts `EquipmentIcons` on a screen.
##
## OWNER: wren.
##
## `Scripts/Art` draws into a `CanvasItem` and never places itself, which is why
## the seventeen item icons existed for a whole merge with no caller. A `Button`
## cannot call a `_draw` function, so sable offered two shapes: a small Control
## beside the text, or a `Texture2D` fed to `Button.icon`. **This is the first.**
## It needs nothing sable has not already shipped, it works today, and it keeps
## the icon at whatever size the layout gives it rather than at a size baked into
## a texture.
##
## Empty is a real state and draws differently from absent: `draw_empty_slot`
## puts the slot's own plate down with no glyph, so an unfilled weapon slot still
## reads as a weapon slot. That is the whole reason `slot` is set even when
## `item` is null.

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
