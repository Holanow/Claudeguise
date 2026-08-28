extends Node

## Issue 737 verification only, not part of the deliverable: runs a fight to
## resolution and shoots the end banner with the new "What happened" ledger
## section on it. Same pattern as `Tools/EndScreenProbe.gd`.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "res://Screenshots"

var _main: Node

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("LedgerScreenshot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
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
	var start := _button("start fight")
	start.emit_signal("pressed")
	await _settle()
	var battle = _node_with("BattleView.gd")
	if battle != null and battle.setup:
		start = _button("start fight")
		start.emit_signal("pressed")
		await _settle()
	battle = _node_with("BattleView.gd")

	battle.set_process(false)
	for i in 4000:
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		battle._process(CG.TICK_SECONDS)
	## The extra process calls give the death flash and the dim fade time to
	## finish before the shot, past what `EndScreenProbe`'s single `_settle`
	## catches mid-animation.
	for i in 60:
		battle._process(CG.TICK_SECONDS)
	await _settle(20)

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/heron_737_ledger.png" % OUT_DIR)
	print("LedgerScreenshot: heron_737_ledger.png")

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null
