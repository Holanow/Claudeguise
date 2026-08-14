extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const EquipmentIcons := preload("res://Scripts/Art/EquipmentIcons.gd")

## Every item icon in the registry, drawn together, at the size the equip screen
## will actually draw them and at the size below that.
##
##   godot --path . --resolution 1280x1000 res://Tools/EquipmentIconSheet.tscn
##
## No --headless. `get_viewport().get_texture()` never populates under --headless
## on this machine; a real window works. Written up in Tools/AttackFXPreview.gd
## and it cost an hour the first time.
##
## THIS IS THE ONLY THING THAT HAS EVER CAUGHT AN ICON COLLISION HERE. Six died
## on the first ability sheet and two more survived that pass into the next one,
## every single one of them behind a table that read correctly. A grid at true
## size is the check; the table is not.
##
## The sheet also draws the three slots' empty plates and the three sizes side by
## side, because "can you tell a weapon slot from an armor slot" is a question
## about the plate and not about any glyph.

const CAPTURE_PATH := "res://Screenshots/equipment_icons_sheet.png"

const _MARGIN := 40.0
const _COLS := 6
const _COL_W := 200.0
const _ROW_H := 108.0

var _font: Font = null

func _ready() -> void:
	# Printed rather than assumed: the project's canvas_items stretch pins the
	# logical viewport near the design width, so `--resolution` is not the drawing
	# space. Laying a sheet out against the window size put a whole column off the
	# edge last time and only a 1:1 crop showed it.
	print("EquipmentIconSheet: logical viewport is ", get_viewport_rect().size)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture()
	get_tree().quit(0)

func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	var err := image.save_png(CAPTURE_PATH)
	if err != OK:
		printerr("EquipmentIconSheet: could not save %s (error %d)" % [CAPTURE_PATH, err])
		return
	print("EquipmentIconSheet: wrote ", CAPTURE_PATH)
	# A 3x nearest-neighbour blow-up as well. A 20px icon cannot be judged from a
	# screenshot somebody views at less than 1:1, and every collision this project
	# has found was found at true size or above it.
	var crop := image.get_region(Rect2i(0, 0, int(get_viewport_rect().size.x), 620))
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png("res://Screenshots/equipment_icons_sheet_x3.png")

func _label(at: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw() -> void:
	_font = ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Palette.BACKGROUND)

	_label(Vector2(_MARGIN, 34.0), "Equipment icons", Palette.FONT_SIZE_HEADING, Palette.TEXT)
	_label(Vector2(_MARGIN, 58.0),
		"Issue 100. Generated defaults -- a PNG dropped into Assets/UI/item/ replaces any of them.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	var y := 84.0
	y = _draw_slot_key(y)
	y = _draw_items(y + 14.0)

## The slot read, on its own, with nothing inside the plates. If a weapon slot
## and an armor slot cannot be told apart empty, the two channels have failed
## and no glyph will rescue them.
func _draw_slot_key(top: float) -> float:
	_label(Vector2(_MARGIN, top),
		"Slots. Empty plates, 40px then 32px then 20px: diamond = weapon, slab = armor, circle = accessory.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	var y := top + 22.0
	draw_rect(Rect2(_MARGIN - 10.0, y - 6.0, 3.0 * 210.0, 62.0), Palette.ARENA_FLOOR)
	var slots := [EquipmentDef.Slot.WEAPON, EquipmentDef.Slot.ARMOR, EquipmentDef.Slot.ACCESSORY]
	for i in slots.size():
		var slot = slots[i]
		var x := _MARGIN + float(i) * 210.0
		EquipmentIcons.draw_empty_slot(self, slot, Rect2(x, y, 40.0, 40.0))
		EquipmentIcons.draw_empty_slot(self, slot, Rect2(x + 46.0, y + 4.0, 32.0, 32.0))
		EquipmentIcons.draw_empty_slot(self, slot, Rect2(x + 84.0, y + 10.0, 20.0, 20.0))
		_label(Vector2(x + 112.0, y + 26.0), String(EquipmentDef.Slot.keys()[slot]).to_lower(),
			Palette.FONT_SIZE_SMALL, EquipmentIcons.slot_color(slot))
	return y + 62.0

func _draw_items(top: float) -> float:
	_label(Vector2(_MARGIN, top),
		"Items, grouped by slot. 40px, then 32px (the equip screen's size), then 20px. plate_mail carries the badge for the action it grants.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	var y := top + 24.0
	# Grouped by slot rather than alphabetically, because the collisions that
	# matter are within a slot: four rings beside each other and three garments
	# beside each other are the two hard cases in this set.
	var ids: Array[StringName] = []
	for slot in [EquipmentDef.Slot.WEAPON, EquipmentDef.Slot.ARMOR, EquipmentDef.Slot.ACCESSORY]:
		for id in Registry.all_equipment_ids():
			if Registry.get_equipment(id).slot == slot:
				ids.append(id)
	for i in ids.size():
		var id: StringName = ids[i]
		var item := Registry.get_equipment(id)
		var x := _MARGIN + float(i % _COLS) * _COL_W
		var cy := y + floorf(float(i) / float(_COLS)) * _ROW_H
		draw_rect(Rect2(x - 6.0, cy - 6.0, 180.0, 92.0), Palette.ARENA_FLOOR)
		EquipmentIcons.draw_item(self, item, Rect2(x, cy, 40.0, 40.0))
		EquipmentIcons.draw_item(self, item, Rect2(x + 48.0, cy + 4.0, 32.0, 32.0))
		EquipmentIcons.draw_item(self, item, Rect2(x + 88.0, cy + 10.0, 20.0, 20.0))
		_label(Vector2(x - 2.0, cy + 60.0), String(id), Palette.FONT_SIZE_SMALL,
			EquipmentIcons.slot_color(item.slot))
		if not item.granted_actions.is_empty():
			_label(Vector2(x - 2.0, cy + 78.0), "grants %s" % item.granted_actions[0],
				Palette.FONT_SIZE_SMALL, Palette.TEXT)
	return y + ceilf(float(ids.size()) / float(_COLS)) * _ROW_H
