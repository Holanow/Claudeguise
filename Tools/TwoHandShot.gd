extends Node

## Issue 917: the Priest's Staff is two-handed, so he starts with no off hand.
## Read off the real equip screen, and it also records what the screen still
## gets wrong -- the off-hand row reads empty rather than occupied, which is
## `EquipPanel`'s half and is not in this branch.

const OUT_DIR := "user://probe"

var _main: Node
var _res_tag: String = ""
var _failures: Array[String] = []

func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("TwoHandShot: %s" % msg)

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("TwoHandShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	printerr("TwoHandShot: %d STEP(S) FAILED:" % _failures.size())
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
	print("TwoHandShot: %s" % path)

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

## One entry list per slot, in `EquipmentDef.Slot` order. Walked from the equip
## panel itself, because the screen around it carries pickers of its own.
func _pickers() -> Array[OptionButton]:
	var out: Array[OptionButton] = []
	var equip: Node = null
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("EquipPanel.gd"):
			equip = n
			break
	if equip == null:
		_fail("no equip panel on the screen")
		return out
	for n in _walk(equip):
		if n is OptionButton:
			out.append(n)
	return out

func _selected(picker: OptionButton) -> String:
	return picker.get_item_text(maxi(picker.selected, 0))

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	if not _focus_class(&"priest"):
		return
	await _settle()
	var pickers := _pickers()
	if pickers.size() < 5:
		_fail("expected a picker per slot, found %d" % pickers.size())
		return
	print("TwoHandShot: priest main hand '%s', off hand '%s'" % [
		_selected(pickers[0]), _selected(pickers[1])])

	var priest := PawnFactory.make_starter_pawn(&"priest", &"probe", "Probe")
	if priest.main_hand == null or not priest.main_hand.two_handed:
		_fail("the Priest's main hand is not two-handed, so this shot proves nothing")
	if priest.off_hand != null:
		_fail("the Priest starts with an off hand as well as a two-hander")
	if _selected(pickers[1]) != EquipPanel.EMPTY_CHOICE:
		_fail("the off-hand picker does not read empty: '%s'" % _selected(pickers[1]))

	## The popup is open on purpose: it is what the screen still gets wrong.
	## The slot reads "(nothing)" rather than "occupied by the Staff", and it
	## still offers a Focus that `PawnData.equipment()` would drop.
	pickers[1].show_popup()
	await _settle()
	var offered: Array[String] = []
	var popup := pickers[1].get_popup()
	for i in popup.item_count:
		if not popup.is_item_disabled(i):
			offered.append(popup.get_item_text(i))
	print("TwoHandShot: the off hand still offers %s" % [offered])
	var sentence := EquipPanel.item_effect_text(priest.main_hand)
	print("TwoHandShot: the Staff reads '%s'" % sentence)
	if not sentence.contains("two-handed"):
		_fail("the equip screen does not say the Staff is two-handed")
	await _shot("teal8_917_priest_two_handed")
	popup.hide()
