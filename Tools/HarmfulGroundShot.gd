extends Node

## Issue 420: the movement dropdown the playtester found short one entry,
## driven through the same control they used.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""

func _ready() -> void:
	if not Offscreen.require_renderer(self):
		return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("HarmfulGroundShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	get_tree().quit(0)

func _settle(frames: int = 6) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s_%s.png" % [OUT_DIR, name, _res_tag]
	image.save_png(path)
	print("HarmfulGroundShot: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _panel() -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("InspectPanel.gd"):
			return n
	return null

## The movement chip is the one offering the interpreter's ops plus the
## no-movement entry, found by its contents rather than by its position.
func _movement_pickers() -> Array[Node]:
	var out: Array[Node] = []
	var panel := _panel()
	if panel == null:
		return out
	for n in _walk(panel):
		if n is OptionButton and n.item_count == PlanInterpreter.MOVEMENT_OPS.size() + 1 \
				and n.get_item_text(0) == InspectPanel.NO_MOVEMENT_CAPTION:
			out.append(n)
	return out

func _button(caption: String) -> Button:
	var panel := _panel()
	if panel == null:
		return null
	for n in _walk(panel):
		if n is Button and n.text == caption and not n.disabled:
			return n
	return null

func _reveal(c: Control) -> void:
	for n in _walk(_panel()):
		if n is ScrollContainer and n.is_ancestor_of(c):
			n.ensure_control_visible(c)
	await _settle()

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	## A class ships with no rows since #399, so the row a player edits has to
	## be added the way a player adds it.
	if _movement_pickers().is_empty():
		var add := _button("+ Add a plan")
		if add == null:
			print("HarmfulGroundShot: no '+ Add a plan' button on the screen")
			return
		add.pressed.emit()
		await _settle(8)

	var pickers := _movement_pickers()
	if pickers.is_empty():
		print("HarmfulGroundShot: no movement picker on the screen")
		return
	var picker: OptionButton = pickers[0]
	await _reveal(picker)
	print("HarmfulGroundShot: the movement dropdown offers --")
	for i in picker.item_count:
		print("HarmfulGroundShot:   %s" % picker.get_item_text(i))
	await _shot("finch_movement_dropdown")

	var wanted := 1 + PlanInterpreter.MOVEMENT_OPS.find(&"leave_harmful_ground")
	picker.selected = wanted
	picker.item_selected.emit(wanted)
	await _settle(8)
	var after := _movement_pickers()
	if after.is_empty():
		print("HarmfulGroundShot: the panel did not rebuild")
		return
	await _reveal(after[0])
	print("HarmfulGroundShot: the row now reads '%s'" % after[0].get_item_text(after[0].selected))
	await _shot("finch_movement_leave_harmful_ground")
