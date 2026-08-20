extends Node

## PLAYTEST-NOTES-2 item 8, photographed through the controls a player presses.
##
##   godot --path . --resolution 1280x720 res://Tools/LogCornerShot.tscn
##   godot --path . --resolution 844x390  res://Tools/LogCornerShot.tscn -- --size 844x390
##
## OWNER: wren. Not part of the game and not part of the gate.
##
## The note is *"the log is too large, move it to a bottom corner, out of the
## way"*, and the two halves want different instruments. **Where** it is, this
## measures: the log's rect and the team status panel's, read off the live nodes
## in viewport pixels, plus the gap between them, so "they overlap" cannot hide
## inside a picture the way a wrong panel height did once already. **How much it
## says**, only the picture answers, so it prints the visible line count and the
## last line drawn beside each shot.
##
## No hand-built state: party select, room picker, Start fight, deploy, Start
## fight, then shots across a running fight, the same route as TeamPanelShot.


const OUT_DIR := "res://Screenshots"
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const ROOM := &"floor1_room1"
const SHOT_TICKS := [60, 200, 340]

var _main: Node
var _suffix := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("LogCornerShot: use a worktree."); get_tree().quit(2); return
	var args := OS.get_cmdline_user_args()
	for i in args.size():
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
	print("LogCornerShot: wrote %s%s.png (%dx%d)" % [name, _suffix, img.get_width(), img.get_height()])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	printerr("LogCornerShot: no button '%s'" % prefix); return false

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
		printerr("LogCornerShot: never reached the battle"); return
	var log_view = battle._combat_log
	if log_view == null:
		printerr("LogCornerShot: THE BATTLE HAS NO COMBAT LOG"); return

	var shot := 0
	for target in SHOT_TICKS:
		var frames := 0
		while battle.state.tick < target \
				and battle.state.outcome == CombatState.Outcome.UNRESOLVED \
				and frames < 200000:
			await get_tree().process_frame
			frames += 1
		shot += 1
		await _settle(2)
		await _shot("log_corner_%d" % shot)
		_report(battle, log_view)

## Read off the live nodes rather than recomputed from the constants. The last
## defect in this column was a height derived from constants that disagreed with
## what Godot draws, and nineteen tests built from the same constants were green
## through it.
func _report(battle, log_view) -> void:
	var view_size: Vector2 = battle.get_viewport_rect().size
	var label: RichTextLabel = log_view._label
	var log_rect := label.get_global_rect()
	var panel_rect: Rect2 = battle._team_status.get_global_rect()
	print("LogCornerShot: tick %d, viewport %.0fx%.0f" % [battle.state.tick, view_size.x, view_size.y])
	print("   log   x %.0f..%.0f  y %.0f..%.0f  (%.0fx%.0f)" % [
		log_rect.position.x, log_rect.end.x, log_rect.position.y, log_rect.end.y,
		log_rect.size.x, log_rect.size.y])
	print("   panel x %.0f..%.0f  y %.0f..%.0f  (%.0fx%.0f)" % [
		panel_rect.position.x, panel_rect.end.x, panel_rect.position.y, panel_rect.end.y,
		panel_rect.size.x, panel_rect.size.y])
	var gap := log_rect.position.y - panel_rect.end.y
	print("   gap between them %.0f px %s" % [gap, "OVERLAP" if gap < 0.0 else ""])
	print("   corner: %.0f px from the right edge, %.0f from the bottom" % [
		view_size.x - log_rect.end.x, view_size.y - log_rect.end.y])
	print("   %d lines of text, %d of them fit in the box; last line: %s" % [
		label.get_line_count(), label.get_visible_line_count(),
		label.get_parsed_text().strip_edges().split("\n")[-1]])
