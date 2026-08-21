extends Node

## Issue 406: the Priest's and the Geysermancer's libraries as the screen draws
## them, through the real pawn tab a player clicks.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _failures := 0

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("CasterLibraryShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	await _run()
	print("CasterLibraryShot: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _settle(n: int = 8) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("CasterLibraryShot: %s.png" % name)

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _click_control(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await _settle(2)

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var select := _node_with("PartySelect.gd")
	if select == null:
		_failures += 1
		return
	var panel = select._inspect_panel
	for class_id in [&"geysermancer", &"priest"]:
		var pawn: PawnData = null
		for p in select.available_pawns():
			if p.pawn_class.id == class_id:
				pawn = p
		if pawn == null or not select._cards.has(pawn.id):
			print("CasterLibraryShot: no %s card on the party screen" % class_id)
			_failures += 1
			continue
		await _click_control(select._cards[pawn.id])
		await _settle()
		print("CasterLibraryShot: showing %s, library open=%s" % [
			panel._pawns[panel._selected_index].pawn_class.id, panel._library_open])
		await _shot("issue406_library_%s" % class_id)
