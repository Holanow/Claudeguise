extends Node

## Issue 32: somebody has to actually play it. Built on the same pattern
## PlaytestRun used for issue 11 -- real Main scene, real party-select
## controls, no synthetic OS input -- because I have no tool that lets me
## watch a live window render in real time. This drives four full fights
## through the real screen and controls and takes screenshots dense enough
## through each one that looking at them afterward is a real look at what
## happened, not just a before/after comparison.
##
##   godot --path . --resolution 1280x720 res://Tools/Issue32Play.tscn
##
## Screenshots land in Screenshots/, named playtest_wren_* per the issue's
## own instruction, not in Tools/preview -- this is the player-facing record,
## not an engineer's tool output.


const OUT_DIR := "res://Screenshots"

## Found before running anything: the real party-select screen offers one
## pawn per class and caps a party at 4, so "class x4" (what SampleFights
## measures) is not a party any real player can ever assemble -- only the
## five leave-one-out combinations of the five classes are reachable
## through the actual screen. Playing all five: real variety, not a rigged
## sample, and it directly answers something SampleFights never could
## ("what does a player who tries every card actually see").
##
## Re-run for the follow-up verdict, now that PartySelect fights the real
## floor1_room1 instead of floor1_ghoul_den. Seeds re-picked from a fresh
## headless search against CG.DEFAULT_ENCOUNTER (removed after) so this
## set is natural variety against the room the game actually loads today,
## not the old ghoul-den-tuned set: four wins and one genuine loss.
const FIGHTS := [
	{"label": "no_warrior", "seed": "2", "classes": ["Priest", "Geysermancer", "Siege Master", "Abomination"]},
	{"label": "no_priest", "seed": "1", "classes": ["Warrior", "Geysermancer", "Siege Master", "Abomination"]},
	{"label": "no_geysermancer", "seed": "2", "classes": ["Warrior", "Priest", "Siege Master", "Abomination"]},
	{"label": "no_siege_master", "seed": "2", "classes": ["Warrior", "Priest", "Geysermancer", "Abomination"]},
	{"label": "no_abomination", "seed": "1", "classes": ["Warrior", "Priest", "Geysermancer", "Siege Master"]},
]

var _main: Node
var _report: Array[String] = []

func _log(s: String) -> void:
	print(s)
	_report.append(s)

## Refuses to run in the main checkout, because it writes into `Screenshots/`
## and that directory is shared and committed.
##
## Added after I ran this tool in the main checkout to verify the encounter fix,
## overwrote 19 of wren's committed playtest frames and left 21 new ones, and
## then could not revert any of it -- discarding working-tree changes in the
## shared checkout is refused, correctly, because that is a different accident
## this project has already had. wren then reported it as their own incident and
## spent time cleaning up something they had not done.
##
## A worktree's `.git` is a file; the main checkout's is a directory. That is
## the whole check, and it turns "remember to use a worktree" into something the
## tool enforces rather than something a person has to hold in their head at
## four in the morning.
func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("Issue32Play: refusing to run in the main checkout -- this tool writes")
		printerr("  into Screenshots/, which is shared and committed. Run it from a")
		printerr("  detached worktree instead:")
		printerr("    git worktree add --detach ../Claudeguise-team/worktrees/play main")
		get_tree().quit(2)
		return
	await _run()
	_write_report()
	get_tree().quit(0)

func _run() -> void:
	for fight in FIGHTS:
		await _play_one_fight(fight)
		_log("")

# ---------------------------------------------------------------------------

func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	image.save_png("%s/%s.png" % [OUT_DIR, name])
	_log("screenshot: %s" % name)

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

## PartyCards, found by shape rather than by class name -- same reasoning as
## LaunchProbe's own fix after this screen moved from CheckBoxes to cards:
## any plain Control (not a Button) carrying a `toggled` signal.
func _party_cards() -> Array:
	var out := []
	for n in _walk(_main):
		if n is Control and not (n is Button) and n.has_signal("toggled"):
			out.append(n)
	return out

func _line_edits() -> Array[LineEdit]:
	var out: Array[LineEdit] = []
	for n in _walk(_main):
		if n is LineEdit:
			out.append(n)
	return out

func _press_named(prefix: String) -> bool:
	for b in _buttons():
		if b.text.to_lower().begins_with(prefix.to_lower()):
			if b.disabled:
				_log("button '%s' is DISABLED, not pressing" % b.text)
				return false
			b.emit_signal("pressed")
			return true
	_log("no button starting with '%s' found" % prefix)
	return false

func _current_screen_name() -> String:
	for c in _main.get_children():
		return c.name
	return "<none>"

# ---------------------------------------------------------------------------

func _play_one_fight(fight: Dictionary) -> void:
	var label: String = fight.label
	_log("=== FIGHT: %s (seed %s) ===" % [label, fight.seed])

	if _main != null:
		_main.queue_free()
		await _settle()

	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	# Click order matters: PartySelect builds the party array in the order
	# cards are pressed, and CombatSim.build assigns party_spawns by index --
	# so clicking in a different order than the headless search used puts
	# the same four classes in different starting positions and can change
	# the outcome for a nominally "same" party. Click in fight.classes's own
	# order, not whatever order the tree happens to return cards in.
	var cards := _party_cards()
	var classes: Array = fight.classes
	var picked_names: Array[String] = []
	for wanted_name in classes:
		for card in cards:
			if card.class_def.display_name == wanted_name:
				card.toggled.emit(true)
				picked_names.append(wanted_name)
				break
	await get_tree().process_frame

	var edits := _line_edits()
	if not edits.is_empty():
		edits[0].text = fight.seed

	await _shot("playtest_wren_%s_00_select" % label)
	_log("classes picked before Start: %s (wanted %s)" % [picked_names, classes])

	_press_named("start")
	await _settle()
	if _current_screen_name() != "Battle":
		_log("did not reach the battle screen for %s; stopping this fight" % label)
		return

	var battle := _main.get_child(0)
	await _shot("playtest_wren_%s_01_start" % label)

	var shots_taken := 0
	var max_wait_frames := 60 * 150 # real fights against floor1_room1 run longer than the ghoul den
	var next_shot_at_tick := 30
	var frames := 0
	while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < max_wait_frames:
		await get_tree().process_frame
		frames += 1
		if battle.state.tick >= next_shot_at_tick and shots_taken < 8:
			shots_taken += 1
			await _shot("playtest_wren_%s_%02d_tick%d" % [label, shots_taken + 1, battle.state.tick])
			next_shot_at_tick += 90 # roughly 1.5s of sim time between shots

	await _shot("playtest_wren_%s_%02d_end" % [label, shots_taken + 2])
	_log("outcome: %s at tick %d (%.1fs), survivors %d/%d, frames waited %d" % [
		CombatState.Outcome.keys()[battle.state.outcome], battle.state.tick,
		float(battle.state.tick) / float(CG.TICKS_PER_SECOND),
		battle.state.living(CG.Team.PLAYER).size(), 4, frames
	])

	# Ground truth, read only after every screenshot for this fight is
	# already saved, so a reaction written from the images stays genuinely
	# blind to it until compared afterward.
	_log("--- event log for %s ---" % label)
	for e in battle.state.events:
		_log("  tick %d  %s  source=%d target=%d amount=%d action=%s" % [
			e.tick, CG.EventKind.keys()[e.kind], e.source_id, e.target_id, e.amount, e.action_id
		])
	_log("--- end event log ---")

func _write_report() -> void:
	var path := ProjectSettings.globalize_path("%s/playtest_wren_report.txt" % OUT_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("Issue32Play: could not write report to ", path)
		return
	f.store_string("\n".join(_report))
	f.close()
	print("Issue32Play: report written to ", path)
