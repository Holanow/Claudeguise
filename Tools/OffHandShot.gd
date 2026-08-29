extends Node

## Issue 746: the shield, focus and quiver rows on the real equip screen,
## through the real picker -- not a `.tres` read, whether the player can
## actually put one on.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""
var _failures: Array[String] = []

func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("OffHandShot: %s" % msg)

func _ready() -> void:
	if not Offscreen.require_renderer(self):
		return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("OffHandShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	printerr("OffHandShot: %d STEP(S) FAILED:" % _failures.size())
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
	print("OffHandShot: %s" % path)

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

func _picker(row_label: String) -> OptionButton:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("EquipPanel.gd"):
			var seen := false
			for c in _walk(n):
				if c is Label and c.text == row_label:
					seen = true
				elif seen and c is OptionButton:
					return c
	_fail("no picker under the '%s' label" % row_label)
	return null

func _equip(row_label: String, item_label: String) -> bool:
	var picker := _picker(row_label)
	if picker == null:
		return false
	for i in picker.item_count:
		if picker.get_item_text(i) == item_label:
			picker.selected = i
			picker.item_selected.emit(i)
			print("OffHandShot: equipped '%s' in %s" % [item_label, row_label])
			return true
	_fail("no '%s' entry '%s'" % [row_label, item_label])
	return false

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	## Bow + Quiver: MARTIAL, ranged, the class the issue names for the bleed.
	if not _focus_class(&"siege_master"):
		return
	await _settle()
	if not _equip("Main Hand", "Bow"):
		return
	if not _equip("Off Hand", "Quiver"):
		return
	await _settle()
	await _shot("heron_746_siege_master_bow_quiver")

	## Sword + Shield: MARTIAL, melee.
	if not _focus_class(&"warrior"):
		return
	await _settle()
	if not _equip("Main Hand", "Sword"):
		return
	if not _equip("Off Hand", "Shield"):
		return
	await _settle()
	await _shot("heron_746_warrior_sword_shield")

	## Staff + Focus: MAGICAL, and the focus grants Channel.
	if not _focus_class(&"priest"):
		return
	await _settle()
	if not _equip("Main Hand", "Staff"):
		return
	if not _equip("Off Hand", "Focus"):
		return
	await _settle()
	await _shot("heron_746_priest_staff_focus")

	_main.queue_free()
	await _settle()
