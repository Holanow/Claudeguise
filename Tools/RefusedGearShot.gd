extends Node

## Issue 474: gear a class cannot wear is refused by omission, so this opens the
## real armour picker's popup and photographs what a player can read in it.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""
var _failures: Array[String] = []

## `SHOT_SUFFIX=_before` names the capture of the behaviour being replaced, so
## the two runs do not overwrite each other.
var _suffix: String = OS.get_environment("SHOT_SUFFIX")

func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("RefusedGearShot: %s" % msg)

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("RefusedGearShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	printerr("RefusedGearShot: %d STEP(S) FAILED:" % _failures.size())
	for f in _failures:
		printerr("  - %s" % f)
	get_tree().quit(3)

func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s%s_%s.png" % [OUT_DIR, name, _suffix, _res_tag]
	image.save_png(path)
	print("RefusedGearShot: %s" % path)

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

func _panel(file: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(file):
			return n
	return null

## The picker on the row whose label is "Armor", found by that label rather than
## by index, because the slot order is EquipPanel's to change.
func _armor_picker() -> OptionButton:
	var equip := _panel("EquipPanel.gd")
	if equip == null:
		_fail("no equip panel on the screen")
		return null
	var seen := false
	for n in _walk(equip):
		if n is Label and n.text == "Armor":
			seen = true
		elif seen and n is OptionButton:
			return n
	_fail("no armour picker under the Armor label")
	return null

## Every entry with whether the player may take it, read off the control rather
## than off `offered_items`. The screen is what the player believes.
func _capture(class_id: StringName, shot_name: String) -> void:
	if not _focus_class(class_id):
		return
	await _settle()
	var picker := _armor_picker()
	if picker == null:
		return
	var offered: Array[String] = []
	var refused: Array[String] = []
	for i in picker.item_count:
		if picker.is_item_disabled(i):
			refused.append(picker.get_item_text(i))
		else:
			offered.append(picker.get_item_text(i))
	print("RefusedGearShot: %s armour offered %s refused %s" % [String(class_id), offered, refused])
	picker.show_popup()
	await _settle()
	var popup := picker.get_popup()
	var screen := int(get_viewport().get_visible_rect().size.y)
	var bottom: int = popup.position.y + popup.size.y
	print("RefusedGearShot: %s popup items=%d top=%d bottom=%d screen=%d fits=%s" % [
		String(class_id), popup.item_count, popup.position.y, bottom, screen, bottom <= screen])
	if popup.item_count == 0:
		_fail("%s armour popup is empty" % class_id)
	await _shot(shot_name)
	popup.hide()
	await _settle()

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	# MARTIAL like the Warrior and not a TANK, so Plate Mail is refused for a
	# reason the method axis alone cannot state.
	await _capture(&"siege_master", "wren_474_siege_master_armour_popup")
	# MAGICAL and a HEALER: refused on both axes at once.
	await _capture(&"priest", "wren_474_priest_armour_popup")
