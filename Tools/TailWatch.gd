extends Node

## Issue 233. Watch a pawnless tail on screen, through the real controls.
##
##   godot --path . --resolution 1280x720 res://Tools/TailWatch.tscn -- --seed 0
##
## `TailAnatomy` says seed 0 of `floor1_warden` runs 25.9 seconds after the last
## pawn dies and that the player's side does nothing at all for 24.5 of them.
## The issue asks whether that reads as dead air, and no headless probe can
## answer that. So: pick the party, pick the room, type the seed, press start,
## and shoot the tail.
##
## Shots are taken by tick, not by wall clock: the last pawn dies at tick 605 on
## this seed, so the tail frames straddle it.


const OUT_DIR := "res://Screenshots"
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const ROOM := &"floor1_warden"
const SHOT_TICKS := [560, 600, 620, 700, 800, 900, 980]

var _main: Node
var _seed := 0

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("TailWatch: use a worktree."); get_tree().quit(2); return
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			_seed = int(args[i + 1])
	await _run()
	get_tree().quit(0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s.png" % [OUT_DIR, name])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	print("TailWatch: no button '%s'" % prefix); return false

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
	var found := -1
	for i in picker.item_count:
		if picker.get_item_metadata(i) == ROOM:
			found = i
	if found < 0:
		print("TailWatch: %s not offered" % ROOM); return
	picker.selected = found
	picker.item_selected.emit(found)
	select._seed_edit.text = "%08X" % _seed
	await _settle()
	if not _press("start fight"): return
	await _settle()
	if not _press("start fight"): return
	await _settle(2)

	var battle := _node_with("BattleView.gd")
	if battle == null:
		print("TailWatch: never reached the battle"); return
	print("TailWatch: seed %08X, room %s" % [battle.state.seed, ROOM])

	var frames := 0
	var next := 0
	var last_pawn_death := -1
	while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < 60 * 150:
		await get_tree().process_frame
		frames += 1
		if last_pawn_death < 0 and _living_pawns(battle.state) == 0:
			last_pawn_death = battle.state.tick
			await _shot("tail_%d_death_t%03d" % [_seed, last_pawn_death])
		while next < SHOT_TICKS.size() and battle.state.tick >= SHOT_TICKS[next]:
			await _shot("tail_%d_t%03d" % [_seed, SHOT_TICKS[next]])
			next += 1
	await _shot("tail_%d_end" % _seed)
	print("TailWatch: outcome=%s tick=%d last_pawn_death=%d" % [
		CombatState.Outcome.keys()[battle.state.outcome], battle.state.tick, last_pawn_death])

static func _living_pawns(state) -> int:
	var n := 0
	for u in state.units:
		if u.alive and u.team == CG.Team.PLAYER and u.pawn != null:
			n += 1
	return n
