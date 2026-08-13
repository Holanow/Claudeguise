extends Node

## Issue 11: drives the real game in-process, through the real controls, and
## answers observation-based questions. Built on the approach LaunchProbe
## pioneered (real Main scene, real Button/CheckBox nodes, no desktop
## takeover, no fixtures) and extended for a full session: edge-case
## interactions on party select, a full fight watched through several
## screenshots, the in-fight controls, and a same-seed multi-party
## comparison.
##
##   godot --path . --resolution 1280x720 res://Tools/PlaytestRun.tscn
##
## Handed to wren for issue 11 by rook; not part of the gate. Everything
## printed here also lands in Tools/preview/playtest_report.txt so the
## board write-up can quote it verbatim.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const OUT_DIR := "res://Tools/preview"
const FIXED_SEED := "0000BEEF"
const BALANCED_PARTY: Array[String] = ["Warrior", "Priest", "Geysermancer", "Siege Master"]

var _main: Node
var _report: Array[String] = []

func _log(s: String) -> void:
	print(s)
	_report.append(s)

func _ready() -> void:
	await _run()
	_write_report()
	get_tree().quit(0)

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	_log("=== PHASE 1: party select edge cases ===")
	await _phase_party_select_edges()

	_log("")
	_log("=== PHASE 2: one full fight, real controls, screenshots as it goes ===")
	await _phase_full_fight()

	_log("")
	_log("=== PHASE 3: in-fight controls (pause, restart, resize, change party) ===")
	await _phase_battle_controls()

	_log("")
	_log("=== PHASE 4: three parties, one seed, outcomes and survivors ===")
	_phase_party_comparison()

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

func _checkboxes() -> Array[CheckBox]:
	var out: Array[CheckBox] = []
	for n in _walk(_main):
		if n is CheckBox:
			out.append(n)
	return out

func _labels() -> Array[Label]:
	var out: Array[Label] = []
	for n in _walk(_main):
		if n is Label:
			out.append(n)
	return out

func _line_edits() -> Array[LineEdit]:
	var out: Array[LineEdit] = []
	for n in _walk(_main):
		if n is LineEdit:
			out.append(n)
	return out

func _label_text_containing(fragment: String) -> String:
	for l in _labels():
		if l.text.contains(fragment):
			return l.text
	return "<not found>"

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

# ---------------------------------------------------------------------------
# Phase 1
# ---------------------------------------------------------------------------

func _phase_party_select_edges() -> void:
	await _shot("play_01_party_select_empty")
	_log("start button disabled with 0 selected: %s" % _start_button_disabled())

	_press_named("start") # a player will just try it
	await _settle()
	_log("pressing Start with 0 selected did anything visible: %s" % (_current_screen_name() != "PartySelect"))

	var boxes := _checkboxes()
	_log("classes offered: %s" % [boxes.map(func(b): return b.text)])
	for b in boxes:
		b.button_pressed = true
		await get_tree().process_frame
	await _shot("play_02_all_five_pressed")
	var checked := boxes.filter(func(b): return b.button_pressed)
	_log("pressed all %d checkboxes; %d ended up checked (want 4): %s" % [boxes.size(), checked.size(), checked.map(func(b): return b.text)])
	_log("status label: %s" % _label_text_containing("Party:"))

	for b in boxes:
		if b.button_pressed:
			b.button_pressed = false
			await get_tree().process_frame

	for b in boxes:
		if BALANCED_PARTY.has(b.text):
			b.button_pressed = true
	await get_tree().process_frame
	_log("status label after selecting the balanced four: %s" % _label_text_containing("Party:"))

	var edits := _line_edits()
	if not edits.is_empty():
		edits[0].text = FIXED_SEED
	await _shot("play_03_party_picked_fixed_seed")

func _start_button_disabled() -> bool:
	for b in _buttons():
		if b.text.to_lower().begins_with("start"):
			return b.disabled
	return true

func _current_screen_name() -> String:
	for c in _main.get_children():
		return c.name
	return "<none>"

# ---------------------------------------------------------------------------
# Phase 2
# ---------------------------------------------------------------------------

func _phase_full_fight() -> void:
	_press_named("start")
	await _settle()
	if _current_screen_name() != "Battle":
		_log("did not reach the battle screen after pressing Start; stopping phase 2")
		return

	var battle := _main.get_child(0)
	await _shot("play_04_battle_start")

	var shots_taken := 0
	var max_wait_frames := 60 * 90 # 90s of frames at 60fps ceiling, well past MAX_TICKS/30
	var next_shot_at_tick := 30 # roughly one second in
	var frames := 0
	while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < max_wait_frames:
		await get_tree().process_frame
		frames += 1
		if battle.state.tick >= next_shot_at_tick and shots_taken < 3:
			shots_taken += 1
			await _shot("play_05_battle_mid_%d_tick%d" % [shots_taken, battle.state.tick])
			next_shot_at_tick += 60 # roughly two more seconds before the next one

	await _shot("play_06_battle_end")
	_log("reached a terminal outcome: %s at tick %d (%.1fs), frames waited: %d" % [
		CombatState.Outcome.keys()[battle.state.outcome], battle.state.tick,
		float(battle.state.tick) / float(CG.TICKS_PER_SECOND), frames
	])
	_log("outcome label on screen: %s" % _label_text_containing("Victory").replace("<not found>", _label_text_containing("Defeat")).replace("<not found>", _label_text_containing("Draw")))

	# The real event log, read only now -- after the screenshots above were
	# already taken -- so the "what do you think happened" answer written
	# from those images (in the board write-up, not here) is genuinely blind
	# to this. This is the ground truth to check that answer against.
	_log("--- real event log for this fight (for comparison against the screenshot-only read) ---")
	for e in battle.state.events:
		_log("  tick %d  %s  source=%d target=%d amount=%d action=%s" % [
			e.tick, CG.EventKind.keys()[e.kind], e.source_id, e.target_id, e.amount, e.action_id
		])
	_log("--- end event log ---")

# ---------------------------------------------------------------------------
# Phase 3
# ---------------------------------------------------------------------------

func _phase_battle_controls() -> void:
	if _current_screen_name() != "Battle":
		_log("not on the battle screen; skipping phase 3")
		return
	var battle := _main.get_child(0)

	_log("attempting resize to a phone-portrait-ish size (390x844) while on the end screen")
	get_window().size = Vector2i(390, 844)
	await _settle()
	await _shot("play_07_resized_390x844")
	get_window().size = Vector2i(1280, 720)
	await _settle()

	_log("pressing Restart (same seed)")
	_press_named("restart")
	await _settle()
	battle = _main.get_child(0)
	_log("after restart: tick=%d outcome=%s (want tick near 0, outcome UNRESOLVED)" % [
		battle.state.tick, CombatState.Outcome.keys()[battle.state.outcome]
	])

	_log("pressing Pause")
	_press_named("pause")
	await _settle()
	var tick_at_pause: int = battle.state.tick
	await _shot("play_08_paused")
	for i in 30:
		await get_tree().process_frame
	_log("30 frames after pausing, tick moved from %d to %d (want: unchanged)" % [tick_at_pause, battle.state.tick])
	_press_named("resume")

	_log("pressing Change party")
	_press_named("change")
	await _settle()
	_log("screen after Change party: %s (want PartySelect)" % _current_screen_name())

# ---------------------------------------------------------------------------
# Phase 4 -- same seed, three+ parties, outcomes and survivors.
# ---------------------------------------------------------------------------

func _phase_party_comparison() -> void:
	var encounter_ids := Registry.all_encounter_ids()
	if encounter_ids.is_empty():
		_log("no encounter registered; cannot compare parties")
		return
	var encounter := Registry.get_encounter(encounter_ids[0])
	var seed := RunConfig.parse_seed(FIXED_SEED)

	var parties := {
		"balanced (warrior/priest/geysermancer/siege_master)": ["warrior", "priest", "geysermancer", "siege_master"],
		"four warriors": ["warrior", "warrior", "warrior", "warrior"],
		"four geysermancers": ["geysermancer", "geysermancer", "geysermancer", "geysermancer"],
	}

	_log("same seed for all: %s" % FIXED_SEED)
	for label in parties:
		var ids: Array = parties[label]
		var party: Array[PawnData] = []
		for i in ids.size():
			party.append(PawnFactory.make_starter_pawn(ids[i], StringName("%s_%d" % [ids[i], i]), String(ids[i])))
		var state := CombatSim.build(party, encounter, seed)
		var outcome := CombatSim.run(state)
		_log("  %-55s -> %-10s ticks=%-4d survivors=%d/%d" % [
			label, CombatState.Outcome.keys()[outcome], state.tick,
			state.living(CG.Team.PLAYER).size(), party.size()
		])

# ---------------------------------------------------------------------------

func _write_report() -> void:
	var path := ProjectSettings.globalize_path("%s/playtest_report.txt" % OUT_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("PlaytestRun: could not write report to ", path)
		return
	f.store_string("\n".join(_report))
	f.close()
	print("PlaytestRun: report written to ", path)
