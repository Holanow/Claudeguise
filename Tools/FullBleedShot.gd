extends Node

## Issue 825. Three shots of the real battle screen at whatever resolution it is
## launched with: mid-fight with the log carrying traffic, the same frame with
## the pause menu open, and placement. Same pattern as `Tools/LedgerScreenshot.gd`.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "res://Screenshots"

## Enough ticks that the log has overflowed its box and is scrolling, and few
## enough that the fight is still a fight.
const TICKS_BEFORE_SHOT := 120

var _main: Node
var _tag := ""
var _prefix := "after"

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("FullBleedShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--prefix="):
			_prefix = arg.substr(9)
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	get_tree().quit(0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _button(prefix: String) -> Button:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			return n
	return null

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var file := "%s_%s_%s.png" % [_prefix, name, _tag]
	img.save_png("%s/%s" % [OUT_DIR, file])
	print("FullBleedShot: %s" % file)

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	var party_ids: Array = ScreenSweepScript.sweep_parties(ClassLibrary.all_ids())[-1]
	for id in party_ids:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()
	_button("start fight").emit_signal("pressed")
	await _settle()

	var battle = _node_with("BattleView.gd")
	if battle != null and battle.setup:
		await _settle(4)
		await _shoot("placement")
		_button("start fight").emit_signal("pressed")
		await _settle()
	battle = _node_with("BattleView.gd")

	battle.set_process(false)
	for i in TICKS_BEFORE_SHOT:
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		battle._process(CG.TICK_SECONDS)
	await _settle(8)
	await _shoot("battle_mid")

	## A real key event through the viewport, not `_toggle_pause_menu()`: the
	## thing being photographed is that Escape reaches the menu at all.
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	get_viewport().push_input(key)
	await _settle(8)
	print("FullBleedShot: menu visible=%s paused=%s" % [
		battle._pause_menu.visible, battle.paused])
	await _shoot("pause_menu")
