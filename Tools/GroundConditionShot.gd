extends Node

## Issue 384: the condition dropdown the player opened in the third blind
## playtest, driven through the same control they used.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""

func _ready() -> void:
	if not Offscreen.require_renderer(self):
		return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("GroundConditionShot: refusing to run in the main checkout -- use a worktree.")
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
	print("GroundConditionShot: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _panel(file: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(file):
			return n
	return null

## Every condition picker on the screen, in row order.
func _condition_pickers() -> Array[Node]:
	var out: Array[Node] = []
	for n in _walk(_panel("InspectPanel.gd")):
		if n is OptionButton and n.item_count == BlockCatalog.CONDITION_OPS.size():
			out.append(n)
	return out

## Scroll whichever container holds `c` until `c` is on screen. Scrolling to the
## bottom instead lands on the Equipment section and captures the wrong thing.
func _reveal(c: Control) -> void:
	for n in _walk(_panel("InspectPanel.gd")):
		if n is ScrollContainer and n.is_ancestor_of(c):
			n.ensure_control_visible(c)
	await _settle()

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	## The plan editor is the landing screen: no navigation to do.
	var pickers := _condition_pickers()
	if pickers.is_empty():
		print("GroundConditionShot: no condition picker on the screen")
		return
	var picker: OptionButton = pickers[0]
	await _reveal(picker)
	print("GroundConditionShot: the dropdown offers --")
	for i in picker.item_count:
		print("GroundConditionShot:   %s" % picker.get_item_text(i))
	await _shot("finch_ground_condition_dropdown")

	# Pick the new entry through the picker's own signal, which is the whole
	# point: the row a player edits has to be the one that changes the plan.
	var wanted := BlockCatalog.CONDITION_OPS.find(&"self_on_harmful_ground")
	picker.selected = wanted
	picker.item_selected.emit(wanted)
	await _settle(8)
	var after := _condition_pickers()
	if after.is_empty():
		print("GroundConditionShot: the panel did not rebuild")
		return
	await _reveal(after[0])
	print("GroundConditionShot: the row now reads '%s'" % after[0].get_item_text(after[0].selected))
	await _shot("finch_ground_condition_picked")
