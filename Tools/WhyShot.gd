extends Node

## Issue 155, photographed through the controls a player presses.
##
##   godot --path . --resolution 1280x720 res://Tools/WhyShot.tscn
##   godot --path . --resolution 844x390  res://Tools/WhyShot.tscn -- --size 844x390
##
## OWNER: wren. Not part of the game and not part of the gate.
##
## Party select, room picker, Start fight, let it run, **Pause**, **Plans**. No
## hand-built state and no direct calls into the panel: the point of this issue
## is a player following a fight, and a screen reached by a function call is a
## screen that may not be reachable at all. This project has shipped twelve
## features built-and-unreachable and the last two were found by fresh readers.
##
## It also prints the plan tags it can see in the running log rather than only
## saving an image, so a failure is legible without opening a PNG.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")

const OUT_DIR := "res://Screenshots"
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const ROOM := &"floor1_room1"
## Far enough in that every pawn has decided something several times, so the log
## carries a mix of plan rows and fallbacks rather than the opening volley.
const PAUSE_AT_TICK := 180

var _main: Node
var _suffix := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("WhyShot: use a worktree."); get_tree().quit(2); return
	for i in OS.get_cmdline_user_args().size():
		var args := OS.get_cmdline_user_args()
		if args[i] == "--size" and i + 1 < args.size():
			_suffix = "_" + args[i + 1]
	await _run()
	get_tree().quit(0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s%s.png" % [OUT_DIR, name, _suffix])
	print("WhyShot: wrote %s%s.png (%dx%d)" % [name, _suffix, img.get_width(), img.get_height()])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	printerr("WhyShot: no button '%s'" % prefix); return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null and PARTY.has(String(n.class_def.id)):
				n.toggled.emit(true)
	await _settle()

	var select := _node_with("PartySelect.gd")
	var picker: OptionButton = select._room_picker
	for i in picker.item_count:
		if picker.get_item_metadata(i) == ROOM:
			picker.selected = i
			picker.item_selected.emit(i)
	await _settle()
	if not _press("start fight"): return
	await _settle()
	if not _press("start fight"): return
	await _settle(2)

	var battle := _node_with("BattleView.gd")
	if battle == null:
		printerr("WhyShot: never reached the battle"); return

	var frames := 0
	while battle.state.tick < PAUSE_AT_TICK \
			and battle.state.outcome == CombatState.Outcome.UNRESOLVED \
			and frames < 200000:
		await get_tree().process_frame
		frames += 1

	if not _press("pause"): return
	await _settle(4)
	await _shot("why_log_paused")
	_report(battle.state)

	if not _press("plans"): return
	await _settle(6)
	await _shot("why_plan_verdicts")
	_report_verdicts(battle)

## The tags actually on screen, read back off the real log view rather than
## recomputed -- a check that rebuilds its own expectation cannot fail.
func _report(state) -> void:
	var log_view := _node_with("CombatLogView.gd")
	var lines: Array[String] = []
	for e in state.events:
		if e.kind != CG.EventKind.ACTION_START:
			continue
		var line: String = log_view.line_for_event(state, e)
		if line.contains("["):
			lines.append(line)
	print("WhyShot: paused at tick %d, %d tagged ACTION_START lines so far" % [state.tick, lines.size()])
	for line in lines.slice(maxi(0, lines.size() - 8)):
		print("   ", line)

func _report_verdicts(battle) -> void:
	var panel := _node_with("InspectPanel.gd")
	if panel == null or not panel.visible:
		printerr("WhyShot: the Plans button did not open the inspect panel"); return
	var words := [panel.VERDICT_ACTING, panel.VERDICT_READY, panel.VERDICT_WAITING, panel.VERDICT_TAUNTED]
	var seen := {}
	for n in _walk(panel):
		if n is Label and words.has(n.text):
			seen[n.text] = int(seen.get(n.text, 0)) + 1
	print("WhyShot: verdicts on the open panel: ", seen)
	if seen.is_empty():
		printerr("WhyShot: the panel opened over a live fight and showed NO verdict at all")
