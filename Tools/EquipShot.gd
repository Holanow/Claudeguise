extends Node

## Issue 100: drive the equip screen the way a player does and photograph what
## happens, including the half that lives on a different screen.
##
##   godot --path . --resolution 1280x720 res://Tools/EquipShot.tscn
##
## Built on ScreenSweep's pattern -- the real Main scene, real controls, no
## synthetic OS input. The sequence is the acceptance criterion of the issue
## written out as steps: open the equip screen, put Plate Mail on the Warrior,
## then walk to the plan editor and look for Directional Block. A unit test can
## assert the last step; only a capture can show it is on the screen.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("EquipShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	get_tree().quit(0)

func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s_%s.png" % [OUT_DIR, name, _res_tag]
	image.save_png(path)
	print("EquipShot: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			if n.disabled:
				print("EquipShot: '%s' is DISABLED" % n.text)
				return false
			n.emit_signal("pressed")
			return true
	print("EquipShot: no visible button starting with '%s'" % prefix)
	return false

func _panel(file: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(file):
			return n
	return null

func _fresh_main() -> void:
	if _main != null:
		_main.queue_free()
		await _settle()
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

func _run() -> void:
	await _fresh_main()
	if not _press("equip pawns"):
		return
	await _settle()
	await _shot("wren_equip_default")

	if not _press("warrior"):
		return
	await _settle()
	await _shot("wren_equip_warrior_empty")

	# The Armor picker, driven by its own item_selected signal rather than by
	# reaching past it into the panel: the point of the capture is that the
	# control a player touches is the one that changes the pawn.
	var equip := _panel("EquipPanel.gd")
	var chosen := ""
	for n in _walk(equip):
		if n is OptionButton:
			for i in n.item_count:
				if n.get_item_text(i) == "Plate Mail":
					n.selected = i
					n.item_selected.emit(i)
					chosen = "Plate Mail"
			if chosen != "":
				break
	print("EquipShot: picked '%s'" % chosen)
	await _settle()
	await _shot("wren_equip_warrior_plate")

	# The numbers and the granted skill sit below the fold at 720 high, which is
	# exactly where a feature goes unseen. Scrolled and photographed separately
	# rather than assumed reachable.
	for n in _walk(equip):
		if n is ScrollContainer and n.custom_minimum_size.x == 0.0:
			n.scroll_vertical = 100000
	await _settle()
	await _shot("wren_equip_warrior_plate_scrolled")

	# The other half of the feature, on the other screen.
	_press("back")
	await _settle()
	if not _press("inspect classes"):
		return
	await _settle()
	_press("warrior")
	await _settle()
	await _shot("wren_equip_plan_editor_top")

	var inspect := _panel("InspectPanel.gd")
	for n in _walk(inspect):
		if n is ScrollContainer:
			n.scroll_vertical = 100000
	await _settle()
	await _shot("wren_equip_plan_editor_blocks")

	# Say in the log what the capture should show, so a wrong capture is
	# recognisable rather than merely unconvincing.
	for n in _walk(inspect):
		if n is OptionButton:
			for i in n.item_count:
				if n.get_item_text(i) == "Directional Block":
					print("EquipShot: 'Directional Block' is offered by a plan-editor picker")
