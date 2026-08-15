extends Node

## Issue 113, photographed through the controls a player presses.
##
##   godot --path . --resolution 1280x720 res://Tools/TeamPanelShot.tscn
##   godot --path . --resolution 844x390  res://Tools/TeamPanelShot.tscn -- --size 844x390
##
## OWNER: wren. Not part of the game and not part of the gate.
##
## Party select, room picker, Start fight, deploy, Start fight, and then shots
## spread across a running fight. No hand-built state and no direct call into
## the panel: this project has shipped twelve features built-and-unreachable and
## every one of them worked when called directly.
##
## It prints what the panel is showing at each shot -- row count, statuses,
## cooldown chips and their seconds -- so a failure is legible without opening a
## PNG, and so "the cooldowns are all empty" cannot hide inside a picture.
##
## The party carries the Siege Master (summons, so the row count has to change
## mid-fight) and the Warrior (five of the game's eight cooldowns).

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const TeamStatusView := preload("res://Scripts/UI/TeamStatusView.gd")
const IconChip := preload("res://Scripts/UI/IconChip.gd")

const OUT_DIR := "res://Screenshots"
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const ROOM := &"floor1_room1"
const SHOT_TICKS := [30, 120, 260]

var _main: Node
var _suffix := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("TeamPanelShot: use a worktree."); get_tree().quit(2); return
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
	print("TeamPanelShot: wrote %s%s.png (%dx%d)" % [name, _suffix, img.get_width(), img.get_height()])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	printerr("TeamPanelShot: no button '%s'" % prefix); return false

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
		printerr("TeamPanelShot: never reached the battle"); return
	var panel = battle._team_status
	if panel == null:
		printerr("TeamPanelShot: THE BATTLE HAS NO TEAM PANEL"); return

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
		await _shot("team_panel_%d" % shot)
		_report(battle, panel)

## Read back off the live panel, not recomputed. A check that rebuilds its own
## expectation from the code under test cannot fail -- rule 3 on the board.
func _report(battle, panel) -> void:
	var state = battle.state
	print("TeamPanelShot: tick %d, %d rows, panel %.0f px of %.0f reserved" % [
		state.tick, panel.row_count(), panel.panel_height(), TeamStatusView.MAX_PANEL_HEIGHT])
	for u in TeamStatusView.rows_for(state):
		var bits: Array[String] = []
		bits.append("%s %d/%d hp" % [u.display_name, maxi(u.hp, 0), u.hp_max])
		if TeamStatusView.is_summon(u):
			print("   ", " | ".join(bits), "  (summon)")
			continue
		bits.append("%d/%d %s" % [u.resource, u.resource_max, CG.ResourceKind.keys()[u.resource_kind].to_lower()])
		var running := TeamStatusView.cooldowns_for(state, u)
		if running.is_empty():
			bits.append(TeamStatusView.cooldown_summary(state, u))
		else:
			for e in running:
				bits.append("%s %s left" % [e["display_name"], TeamStatusView.seconds_text(int(e["ticks_left"]))])
		print("   ", " | ".join(bits))
	# And what is actually on the screen, which is a different question from what
	# the data says: a chip can be configured and invisible.
	var chips := 0
	var defined := 0
	for n in _walk(panel):
		if n.get_script() == IconChip and n.visible:
			chips += 1
			if n.tooltip_text.strip_edges().length() > 10:
				defined += 1
	print("   %d chips drawn, %d of them carrying a definition" % [chips, defined])
