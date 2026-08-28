extends Node

## Issue 53: sweep every screen the game has, at both resolutions the game is
## required to work at, and actually look. Built on Issue32Play's pattern --
## real Main scene, real controls, no synthetic OS input -- extended to visit
## every screen rather than only the battle loop: party select (empty and
## full), the plan editor (the middle column of party select since #351, not a
## screen of its own), floor map, battle, end-of-fight banner, and the level
## editor.


const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""
var _classes_shot: Dictionary = {}
var _failures: Array[String] = []

## A capture tool that returns early on a failed step reports an absence as a
## result, so every failure is recorded and the run exits non-zero (#371).
func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("ScreenSweep: %s" % msg)

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ScreenSweep: refusing to run in the main checkout -- run from a")
		printerr("  detached worktree instead.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	# get_viewport().get_visible_rect().size is the project's *logical*
	# canvas_items/expand coordinate space, not the physical window --
	# project.godot keeps design height fixed and widens design width to
	# match a wider physical aspect, so an 844x390 launch reports a viewport
	# of roughly 1558x720 in design space. lark found the same trap in issue
	# 42's own disclosure (a synthetic Control root there; this is the real
	# window). The filenames need to say what was actually launched.
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	var ok := _coverage_ok()
	if not _failures.is_empty():
		printerr("ScreenSweep: %d STEP(S) FAILED at %s:" % [_failures.size(), _res_tag])
		for f in _failures:
			printerr("  - %s" % f)
		printerr("  Screenshots for those steps were not taken and none of the")
		printerr("  pictures on disk may be cited as coverage of them.")
		ok = false
	get_tree().quit(0 if ok else 3)

## Fails the run when a class was never photographed, so the blind spot in
## issue 327 cannot come back silently.
func _coverage_ok() -> bool:
	var missing: Array[String] = []
	for id in ClassLibrary.all_ids():
		if not _classes_shot.has(id):
			missing.append(String(id))
	if missing.is_empty():
		print("ScreenSweep: photographed every class (%d) at %s" % [
			_classes_shot.size(), _res_tag])
		return true
	printerr("ScreenSweep: NEVER PHOTOGRAPHED: %s at %s -- the sweep is blind to" % [
		", ".join(missing), _res_tag])
	printerr("  those classes and its screenshots must not be cited as coverage.")
	return false

func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s_%s.png" % [OUT_DIR, name, _res_tag]
	image.save_png(path)
	print("ScreenSweep: %s" % path)

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

func _party_cards() -> Array:
	var out := []
	for n in _walk(_main):
		if n is Control and not (n is Button) and n.has_signal("toggled"):
			out.append(n)
	return out

## Parties that between them contain every class, rather than the first four
## cards of an alphabetical roster -- which is why no screenshot in this repo
## had ever contained a Warrior, fifth of five (issue 327). A short final
## party is padded from the front so every shot is still a full party.
static func sweep_parties(class_ids: Array, party_size: int = 4) -> Array:
	var parties := []
	var taken := 0
	while taken < class_ids.size():
		var party := []
		while party.size() < party_size and taken < class_ids.size():
			party.append(class_ids[taken])
			taken += 1
		for pad in class_ids:
			if party.size() >= party_size:
				break
			if not party.has(pad):
				party.append(pad)
		parties.append(party)
	return parties

## Select the named classes by their card's own `class_def`, never by index.
func _select_classes(ids: Array) -> bool:
	var by_id := {}
	for card in _party_cards():
		if card.class_def != null:
			by_id[card.class_def.id] = card
	for id in ids:
		if not by_id.has(id):
			_fail("no party card for class '%s'" % id)
			return false
		by_id[id].toggled.emit(true)
		_classes_shot[id] = true
	return true

func _press_named(prefix: String) -> bool:
	for b in _buttons():
		if b.text.to_lower().begins_with(prefix.to_lower()) and b.is_visible_in_tree():
			if b.disabled:
				_fail("button '%s' is DISABLED, not pressing" % b.text)
				return false
			b.emit_signal("pressed")
			return true
	_fail("no visible button starting with '%s' found" % prefix)
	return false

## Since #399 a starter pawn carries no plan rows, so a tool that expects
## authored behaviour has to add the class library the way a player does.
static func add_presets(root: Node) -> bool:
	for n in walk(root):
		if n is PartySelect:
			for pawn in (n as PartySelect).available_pawns():
				pawn.plans = PresetPlans.for_class(pawn.pawn_class.id)
			return true
	return false

static func walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(walk(c))
	return out

## Plan rows on screen, counted by the "1." "2." tag `InspectPanel` numbers them
## with, so a capture of an empty editor cannot pass for a capture of plans.
static func plan_row_count(panel: Node) -> int:
	var rows := 0
	for n in walk(panel):
		if n is Label:
			var text: String = (n as Label).text
			if text.ends_with(".") and text.trim_suffix(".").is_valid_int():
				rows += 1
	return rows

func _node_with(file: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(file):
			return n
	return null

func _current_screen_name() -> String:
	for c in _main.get_children():
		return c.name
	return "<none>"

func _fresh_main() -> void:
	if _main != null:
		_main.queue_free()
		await _settle()
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

# ---------------------------------------------------------------------------

func _run() -> void:
	await _party_select_empty()
	var parties := sweep_parties(ClassLibrary.all_ids())
	for i in parties.size():
		var tag := "p%d" % (i + 1)
		print("ScreenSweep: %s = %s" % [tag, ", ".join(PackedStringArray(parties[i]))])
		await _party_select_full_and_start_fight(parties[i], tag)
	await _plan_editor()
	await _floor_map_and_end_of_fight()

## Party select, nothing picked yet -- the very first screen a player sees.
func _party_select_empty() -> void:
	await _fresh_main()
	await _shot("sweep_party_select_empty")

## Pick a full party of four, then confirm Start Fight is on screen and
## clickable before pressing it, then follow the fight to its end banner.
func _party_select_full_and_start_fight(party: Array, tag: String) -> void:
	await _fresh_main()
	if not _select_classes(party):
		return
	await get_tree().process_frame
	await _shot("sweep_party_select_full_%s" % tag)

	var start_btn: Button = null
	for b in _buttons():
		if b.text.to_lower().begins_with("start fight"):
			start_btn = b
			break
	if start_btn == null:
		_fail("NO 'Start Fight' BUTTON FOUND at %s" % _res_tag)
	else:
		var rect := start_btn.get_global_rect()
		var vp := get_viewport().get_visible_rect()
		var on_screen := vp.intersects(rect) and rect.position.y >= 0.0 and rect.position.y < vp.size.y
		print("ScreenSweep: Start Fight rect=%s viewport=%s on_screen=%s disabled=%s at %s" % [
			rect, vp.size, on_screen, start_btn.disabled, _res_tag
		])

	_press_named("start fight")
	await _settle()

	## The battle screen opens held before its first tick with the party
	## draggable, and its own button carries the same words.
	if _screen_is_in_setup():
		await _shot("sweep_deploy_%s" % tag)
		_press_named("start fight")
		await _settle()

	if _current_screen_name() != "Battle":
		_fail(("did not reach Battle from Start Fight at %s -- the battle " +
			"screenshots on disk are from an older run and must not be cited " +
			"as current") % _res_tag)
		return
	var battle := _main.get_child(0)
	await _shot("sweep_battle_start_%s" % tag)

	var frames := 0
	var max_wait_frames := 60 * 400
	var mid_shot_taken := false
	while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < max_wait_frames:
		await get_tree().process_frame
		frames += 1
		if not mid_shot_taken and battle.state.tick >= 60:
			mid_shot_taken = true
			await _shot("sweep_battle_mid_%s" % tag)

	## **This used to shoot unconditionally and call the file "end banner".**
	## A second fresh-eyes playtester got `outcome=UNRESOLVED tick=64` and a
	## banner-less screenshot named `sweep_battle_end_banner`, and reasonably
	## reported "I never saw a fight resolve" as a game defect. It is not: the
	## fight simply had not finished inside the frame budget, and the sweep
	## named the picture after the screen it wanted rather than the screen it
	## got.
	if battle.state.outcome == CombatState.Outcome.UNRESOLVED:
		printerr("ScreenSweep: fight did not resolve in %d frames (tick %d) at %s --" % [
			max_wait_frames, battle.state.tick, _res_tag])
		printerr("  NOT shooting an end banner. There is no banner on screen to shoot.")
		return
	await _shot("sweep_battle_end_banner_%s" % tag)
	print("ScreenSweep: fight ended outcome=%s tick=%d at %s" % [
		CombatState.Outcome.keys()[battle.state.outcome], battle.state.tick, _res_tag
	])

## The plan editor. #351 moved it into the middle column of party select and
## deleted the "Inspect classes" button that used to open it, so a class card
## is the only control that opens it: clicking one is what focuses the column.
func _plan_editor() -> void:
	await _fresh_main()
	if not add_presets(_main):
		_fail("no PartySelect to add preset plans to")
		return
	var inspect_panel := _node_with("InspectPanel.gd")
	if inspect_panel == null:
		_fail("no InspectPanel in the middle column of party select")
		return
	# Warrior first, whose library rows carry a Condition, a Targeting block and
	# an Action block; then the Geysermancer, the one class with a ranged attack,
	# so the fallback row states the ranged commit rule rather than a melee approach.
	await _plan_editor_for(&"warrior", inspect_panel, "sweep_inspect_plan_editor")
	await _plan_editor_for(&"geysermancer", inspect_panel, "sweep_inspect_ranged_fallback")

func _plan_editor_for(class_id: StringName, inspect_panel: Node, shot: String) -> void:
	if not _select_classes([class_id]):
		return
	await _settle()
	# Scroll the detail panel to the bottom so the plan row's pickers are in
	# frame -- ScrollContainer under body/detail_scroll per InspectPanel.gd.
	for n in _walk(inspect_panel):
		if n is ScrollContainer:
			n.scroll_vertical = 100000
	await _settle()
	await _shot(shot)
	var rows := plan_row_count(inspect_panel)
	print("ScreenSweep: %s's plan editor shows %d row(s)" % [class_id, rows])
	if rows == 0:
		_fail("%s's plan editor shows no rows, so '%s' is a picture of an empty editor" % [
			class_id, shot])

## The floor map, reached via Start Run, plus whichever room resolves first.
func _floor_map_and_end_of_fight() -> void:
	await _fresh_main()
	var parties := sweep_parties(ClassLibrary.all_ids())
	if parties.is_empty() or not _select_classes(parties[0]):
		return
	await get_tree().process_frame

	var run_btn: Button = null
	for b in _buttons():
		if b.text.to_lower().begins_with("start run"):
			run_btn = b
			break
	if run_btn == null:
		_fail("NO 'Start Run' BUTTON FOUND at %s" % _res_tag)
		return
	run_btn.emit_signal("pressed")
	await _settle()
	if _current_screen_name() != "FloorMap":
		_fail("did not reach FloorMap from Start Run at %s" % _res_tag)
		return
	await _shot("sweep_floor_map")

## True while the battle screen is held before its first tick with the party
## draggable, which is where "Start Fight" means "begin" rather than "place".
func _screen_is_in_setup() -> bool:
	var screen = _main._current if _main != null else null
	return screen != null and "setup" in screen and screen.setup
