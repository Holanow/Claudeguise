extends Node

## Issue 11: drives the real game in-process, through the real controls, and
## answers observation-based questions. Built on the approach LaunchProbe
## pioneered (real Main scene, real Button/CheckBox nodes, no desktop
## takeover, no fixtures) and extended for a full session: edge-case
## interactions on party select, a full fight watched through several
## screenshots, the in-fight controls, and a same-seed multi-party
## comparison.


const OUT_DIR := "res://Tools/preview"
const FIXED_SEED := "0000BEEF"
const BALANCED_PARTY: Array[String] = ["Warrior", "Priest", "Geysermancer", "Siege Master"]

var _main: Node
var _report: Array[String] = []
var _failed: bool = false

func _log(s: String) -> void:
	print(s)
	_report.append(s)

func _ready() -> void:
	Offscreen.hide_window(self)
	_clear_outputs()
	await _run()
	_write_report()
	get_tree().quit(1 if _failed else 0)

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

## Party select has not used CheckBox since the class cards landed; this
## returned an empty array, nothing was ever selected, and every phase after
## phase 1 died on a Start button that reads "Pick a party to fight" while
## disabled (issue 328).
func _party_cards() -> Array:
	var out := []
	for n in _walk(_main):
		if n is Control and not (n is Button) and n.has_signal("toggled"):
			out.append(n)
	return out

func _card_name(card) -> String:
	return card.class_def.display_name if card.class_def != null else "<no class>"

func _party_select() -> Node:
	for n in _walk(_main):
		if n is PartySelect:
			return n
	return null

func _selected_count() -> int:
	var screen := _party_select()
	return screen.selected_pawns().size() if screen != null else -1

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

	var fight_btn := _start_button() # a player will just try it
	if fight_btn != null and not fight_btn.disabled:
		fight_btn.pressed.emit()
	await _settle()
	_log("pressing '%s' with 0 selected did anything visible: %s" % [
		"<none>" if fight_btn == null else fight_btn.text,
		_current_screen_name() != "PartySelect"])

	var cards := _party_cards()
	_log("classes offered: %s" % [cards.map(_card_name)])
	if cards.is_empty():
		_log("NO CLASS CARDS FOUND -- party select changed shape; the rest of this run is meaningless")
		_failed = true
		return
	for c in cards:
		c.toggled.emit(true)
		await get_tree().process_frame
	await _shot("play_02_all_five_pressed")
	_log("pressed all %d cards; %d ended up selected (want 4)" % [cards.size(), _selected_count()])
	_log("status label: %s" % _label_text_containing("Party"))

	for c in cards:
		if c.selected:
			c.toggled.emit(false)
			await get_tree().process_frame

	for c in cards:
		if BALANCED_PARTY.has(_card_name(c)):
			c.toggled.emit(true)
	await get_tree().process_frame
	_log("selected the balanced four: %s" % [cards.filter(func(c): return c.selected).map(_card_name)])
	_log("status label after selecting the balanced four: %s" % _label_text_containing("Party:"))

	var edits := _line_edits()
	if not edits.is_empty():
		edits[0].text = FIXED_SEED
	await _shot("play_03_party_picked_fixed_seed")

## Both labels the fight button wears: it reads "Pick a party to fight" while
## disabled, so a prefix match on "start" cannot find it with nothing selected.
func _start_button() -> Button:
	for b in _buttons():
		var t := b.text.to_lower()
		if t.begins_with("start fight") or t.begins_with("pick a party to fight"):
			return b
	return null

func _start_button_disabled() -> bool:
	var b := _start_button()
	if b == null:
		_log("NO FIGHT BUTTON ON SCREEN AT ALL")
		return false
	return b.disabled

func _current_screen_name() -> String:
	for c in _main.get_children():
		return c.name
	return "<none>"

# ---------------------------------------------------------------------------
# Phase 2
# ---------------------------------------------------------------------------

func _phase_full_fight() -> void:
	_press_named("start fight")
	await _settle()
	## The battle screen opens held before its first tick with the party
	## draggable, and its own button carries the same words.
	if _screen_is_in_setup():
		await _shot("play_03b_deploy")
		_press_named("start fight")
		await _settle()
	if _current_screen_name() != "Battle":
		_log("DID NOT REACH THE BATTLE SCREEN (on %s); stopping phase 2" % _current_screen_name())
		_failed = true
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
		_failed = true
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

	## Let the restarted fight tick first. Pausing at tick 0 and reporting
	## "0 to 0" proves nothing: an unpaused fight would have shown the same.
	for i in 60:
		await get_tree().process_frame
	_log("pressing Pause at tick %d" % battle.state.tick)
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
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
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

## Every output this tool writes, removed before it starts. A half-finished run
## that leaves the last one's screenshots in place is an instrument that lies
## (issue 328): `play_04` through `play_08` sat on disk for eight days looking
## current while phase 2 had not run at all.
func _clear_outputs() -> void:
	var dir_path := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		printerr("PlaytestRun: cannot open %s to clear it; refusing to run" % dir_path)
		get_tree().quit(2)
		return
	var removed := 0
	for entry in dir.get_files():
		if entry.begins_with("play_") or entry == "playtest_report.txt":
			dir.remove(entry)
			removed += 1
	print("PlaytestRun: cleared %d previous output(s) from %s" % [removed, OUT_DIR])

func _write_report() -> void:
	var path := ProjectSettings.globalize_path("%s/playtest_report.txt" % OUT_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("PlaytestRun: could not write report to ", path)
		return
	f.store_string("\n".join(_report))
	f.close()
	print("PlaytestRun: report written to ", path)

## True while the battle screen is held before its first tick with the party
## draggable, which is where "Start Fight" means "begin" rather than "place".
func _screen_is_in_setup() -> bool:
	var screen = _main._current if _main != null else null
	return screen != null and "setup" in screen and screen.setup
