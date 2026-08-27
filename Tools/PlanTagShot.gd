extends Node

## Issue 441: what the log says when a pawn has no plan, read off the real
## screen rather than off `line_for_event`. The log box is 260x200, so the shot
## is cropped to it and doubled -- a 1280x720 frame cannot show a dim 12px tag.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "res://Screenshots"
const STOP_TICK := 60

var _main: Node

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("PlanTagShot: refusing to run in the main checkout -- use a worktree.")
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

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	return false

func _shot(name: String, box: Rect2) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var region := Rect2i(box).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(region)
	crop.resize(region.size.x * 2, region.size.y * 2, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	crop.save_png("%s/%s.png" % [OUT_DIR, name])
	print("PlanTagShot: %s.png" % name)

func _to_battle() -> Node:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	for id in ScreenSweepScript.sweep_parties(ClassLibrary.all_ids())[-1]:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()
	if not _press("start fight"):
		return null
	await _settle()
	## The battle screen opens held before its first tick with the party
	## draggable, and its own button carries the same words.
	var held = _node_with("BattleView.gd")
	if held != null and held.setup:
		if not _press("start fight"):
			return null
		await _settle()
	return _node_with("BattleView.gd")

func _run() -> bool:
	var battle := await _to_battle()
	if battle == null:
		print("PlanTagShot: never reached the battle screen")
		return false
	var log_view := _node_with("CombatLogView.gd")
	battle.set_process(false)
	for i in STOP_TICK:
		battle._process(CG.TICK_SECONDS)
	await _settle()
	await _shot("wren_441_log_no_plan_tag", log_view._label.get_global_rect().grow(8.0))

	var tagged := 0
	for line in log_view._label.get_parsed_text().split("\n"):
		if line.contains("[no plan]"):
			tagged += 1
		if line.to_lower().contains("fallback"):
			print("PlanTagShot: FAIL the log still says fallback: %s" % line)
			return false
	print("PlanTagShot: %d visible lines carry [no plan], 0 say fallback" % tagged)
	return tagged > 0
