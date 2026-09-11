extends Node

## Issue 918's evidence: the README's floor 1 base types on the real equip
## screen, read off the real pickers. Two panels in one PNG -- a martial class
## and a magical one -- because `Screenshots/` holds one image per issue, and
## the gate is Method-crossed-with-Style so one class cannot show it.
##
##   run.ps1 BaseTypesShot -FixedFps 60

const OUT_DIR := "user://probe"

var _main: Node
var _panels: Array[Image] = []
var _failures: Array[String] = []

func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("BaseTypesShot: %s" % msg)

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	printerr("BaseTypesShot: %d STEP(S) FAILED:" % _failures.size())
	for f in _failures:
		printerr("  - %s" % f)
	get_tree().quit(3)

func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _focus_class(class_id: StringName) -> bool:
	for n in _walk(_main):
		if n is PartyCard and (n as PartyCard).class_def != null \
				and (n as PartyCard).class_def.id == class_id:
			n.toggled.emit(true)
			return true
	_fail("no party card for class '%s'" % class_id)
	return false

## Every picker on the equip screen, one per `EquipmentDef.Slot` in enum order.
func _pickers() -> Array[OptionButton]:
	var out: Array[OptionButton] = []
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("EquipPanel.gd"):
			for c in _walk(n):
				if c is OptionButton:
					out.append(c)
	return out

func _report(class_id: StringName) -> void:
	var pickers := _pickers()
	if pickers.size() != 5:
		_fail("%s: expected one picker per slot, found %d" % [class_id, pickers.size()])
		return
	for i in pickers.size():
		var entries: Array[String] = []
		for j in pickers[i].item_count:
			entries.append(pickers[i].get_item_text(j))
		print("BaseTypesShot: %s %s -> %s" % [
			String(class_id), EquipPanel.slot_name(i), entries])

## The paper doll sits above the five slot rows and the rows are what this shot
## is about, so the detail column is scrolled past it.
func _scroll_to_the_slot_rows() -> void:
	var pickers := _pickers()
	if pickers.is_empty():
		return
	for n in _walk(_main):
		if n is ScrollContainer and n.name == &"DetailScroll":
			var scroll := n as ScrollContainer
			scroll.scroll_vertical += int(
				pickers[0].global_position.y - scroll.global_position.y) - 40

func _grab() -> void:
	await RenderingServer.frame_post_draw
	_panels.append(get_viewport().get_texture().get_image())

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting(
		"application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	for class_id in [&"warrior", &"priest"]:
		if not _focus_class(class_id):
			return
		await _settle()
		_report(class_id)
		_scroll_to_the_slot_rows()
		await _settle()
		await _grab()
	_write()

func _write() -> void:
	var size := _panels[0].get_size()
	var sheet := Image.create(size.x * _panels.size(), size.y, false, _panels[0].get_format())
	for i in _panels.size():
		sheet.blit_rect(_panels[i], Rect2i(Vector2i.ZERO, size), Vector2i(size.x * i, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/kestrel8_918_floor_one_base_types.png" % OUT_DIR
	sheet.save_png(path)
	print("BaseTypesShot: wrote %s" % path)
