extends Node

## Issue 915: gear gates on Method crossed with Style and on no role, so body
## armour gates on Method alone. Read off the real armour picker in the real
## party-select middle column, one class at a time, the way a player meets it.

const OUT_DIR := "user://probe"

var _main: Node
var _res_tag: String = ""
var _failures: Array[String] = []

func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("GearTagShot: %s" % msg)

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("GearTagShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	printerr("GearTagShot: %d STEP(S) FAILED:" % _failures.size())
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
	var path := "%s/%s_%s.png" % [OUT_DIR, name, _res_tag]
	image.save_png(path)
	print("GearTagShot: %s" % path)

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

## Every entry of the armour picker, read off the control itself rather than
## off `offered_items`. The screen is what the player believes.
func _armor_entries() -> Array[String]:
	var equip := _panel("EquipPanel.gd")
	if equip == null:
		_fail("no equip panel on the screen")
		return []
	var pickers: Array[OptionButton] = []
	for n in _walk(equip):
		if n is OptionButton:
			pickers.append(n)
	## Index 3 is BODY: the panel builds one picker per slot in
	## `EquipmentDef.Slot` order, and it has done since #745 split five slots
	## out of three.
	if pickers.size() < 5:
		_fail("expected a picker per slot, found %d" % pickers.size())
		return []
	var out: Array[String] = []
	for i in pickers[3].item_count:
		out.append(pickers[3].get_item_text(i))
	return out

func _report(class_id: StringName, must_offer: Array[String], must_refuse: Array[String]) -> void:
	var entries := _armor_entries()
	print("GearTagShot: %s is offered armour %s" % [String(class_id), entries])
	for label in must_offer:
		if not entries.has(label):
			_fail("%s should be offered '%s' and the picker does not list it" % [class_id, label])
	for label in must_refuse:
		if entries.has(label):
			_fail("%s should be refused '%s' and the picker lists it" % [class_id, label])

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	# MARTIAL, so both martial bodies and neither magical one.
	if not _focus_class(&"warrior"):
		return
	await _settle()
	_report(&"warrior", ["Plate Mail", "Silk Wraps"], ["Robes", "Gown"])
	await _shot("teal8_915_warrior_armour")

	# MAGICAL, so the opposite pair. The method axis is the whole gate here.
	if not _focus_class(&"priest"):
		return
	await _settle()
	_report(&"priest", ["Robes", "Gown"], ["Plate Mail", "Silk Wraps"])
	await _shot("teal8_915_priest_armour")

	# The class #915 was blocked on: MARTIAL and SUMMONER, refused all sixteen
	# base types under a Method-and-Style body gate and offered Plate under this
	# one.
	if not _focus_class(&"siege_master"):
		return
	await _settle()
	_report(&"siege_master", ["Plate Mail", "Silk Wraps"], ["Robes", "Gown"])
	await _shot("teal8_915_siege_master_armour")
