extends Node

## Issue 771/764/765: proof the Siege Master's mark row reads "the farthest
## enemy" on the real plan screen, not just in `PresetPlans.gd`'s source.

const OUT_DIR := "res://Screenshots"

var _main: Node

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("Wren771Shot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

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

func _shot(name: String, box: Rect2) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var region := Rect2i(box).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(region)
	crop.resize(region.size.x * 2, region.size.y * 2, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	crop.save_png("%s/%s.png" % [OUT_DIR, name])
	print("Wren771Shot: %s.png" % name)

func _run() -> bool:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	if not by_id.has(&"siege_master"):
		print("Wren771Shot: no Siege Master card")
		return false
	by_id[&"siege_master"].toggled.emit(true)
	await _settle()

	var select := _node_with("PartySelect.gd")
	print("Wren771Shot: focused %s" % select.focused_pawn().display_name)
	var panel := _node_with("InspectPanel.gd")
	await _shot("wren_771_siege_master_mark_row", panel.get_global_rect())

	var found := false
	for n in _walk(panel):
		if n is Label and n.text.contains("farthest enemy"):
			found = true
	print("Wren771Shot: 'farthest enemy' visible in panel: %s" % found)
	return found
