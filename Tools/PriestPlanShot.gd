extends Node

## Issue 138: the Priest's plan list, on screen, through the controls a player
## uses.
##
##   godot --path . --resolution 1280x720 res://Tools/PriestPlanShot.tscn
##
## `Tools/ScreenSweep.gd` selects the Warrior, so the reserve this issue adds is
## in no existing screenshot. The point of the change is that the reserve is
## *readable* -- issue 98's principle -- and a gate full of green assertions
## says nothing about whether the row renders. Same route ScreenSweep takes:
## real Main scene, real buttons, no synthetic OS input.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("PriestPlanShot: refusing to run in the main checkout")
		get_tree().quit(2)
		return
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	if not _press_named("inspect classes"):
		get_tree().quit(1)
		return
	await _settle()
	for b in _buttons():
		if b.text == "Priest":
			b.emit_signal("pressed")
			break
	await _settle()
	await _shot("priest_plans_reserve_top")

	for n in _walk(_main):
		if n is ScrollContainer:
			n.scroll_vertical = 100000
	await _settle()
	await _shot("priest_plans_reserve")
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
	print("PriestPlanShot: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	for n in _walk(_main):
		if n is Button:
			out.append(n)
	return out

func _press_named(prefix: String) -> bool:
	for b in _buttons():
		if b.text.to_lower().begins_with(prefix.to_lower()) and b.is_visible_in_tree() and not b.disabled:
			b.emit_signal("pressed")
			return true
	print("PriestPlanShot: no visible button starting with '%s'" % prefix)
	return false
