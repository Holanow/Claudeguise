extends Node

## Issue 53: sweep every screen the game has, at both resolutions the game is
## required to work at, and actually look. Built on Issue32Play's pattern --
## real Main scene, real controls, no synthetic OS input -- extended to visit
## every screen rather than only the battle loop: party select (empty and
## full), inspect (which is also where the plan editor lives -- there is no
## separate plan-editor screen, see InspectPanel.gd), floor map, battle,
## end-of-fight banner, and the level editor.


const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""
var _classes_shot: Dictionary = {}

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
	get_tree().quit(0 if _coverage_ok() else 3)

## Fails the run when a class was never photographed, so the blind spot in
## issue 327 cannot come back silently.
func _coverage_ok() -> bool:
	var missing: Array[String] = []
	for id in Registry.all_class_ids():
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
			printerr("ScreenSweep: no party card for class '%s'" % id)
			return false
		by_id[id].toggled.emit(true)
		_classes_shot[id] = true
	return true

func _press_named(prefix: String) -> bool:
	for b in _buttons():
		if b.text.to_lower().begins_with(prefix.to_lower()) and b.is_visible_in_tree():
			if b.disabled:
				print("ScreenSweep: button '%s' is DISABLED, not pressing" % b.text)
				return false
			b.emit_signal("pressed")
			return true
	print("ScreenSweep: no visible button starting with '%s' found" % prefix)
	return false

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
	var parties := sweep_parties(Registry.all_class_ids())
	for i in parties.size():
		var tag := "p%d" % (i + 1)
		print("ScreenSweep: %s = %s" % [tag, ", ".join(PackedStringArray(parties[i]))])
		await _party_select_full_and_start_fight(parties[i], tag)
	await _inspect_from_party_select()
	await _level_editor()
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
		print("ScreenSweep: NO 'Start Fight' BUTTON FOUND at %s" % _res_tag)
	else:
		var rect := start_btn.get_global_rect()
		var vp := get_viewport().get_visible_rect()
		var on_screen := vp.intersects(rect) and rect.position.y >= 0.0 and rect.position.y < vp.size.y
		print("ScreenSweep: Start Fight rect=%s viewport=%s on_screen=%s disabled=%s at %s" % [
			rect, vp.size, on_screen, start_btn.disabled, _res_tag
		])

	_press_named("start fight")
	await _settle()

	## Issue 145 put a deploy screen between party select and the fight, so
	## "Start Fight" now means "go and place your party" and there is a second
	## Start Fight on the deploy screen itself.
	if _current_screen_name() == "Deploy":
		await _shot("sweep_deploy_%s" % tag)
		_press_named("start fight")
		await _settle()

	if _current_screen_name() != "Battle":
		printerr("ScreenSweep: did not reach Battle from Start Fight at %s -- the")
		printerr("  battle screenshots on disk are from an older run and must not")
		printerr("  be cited as current.")
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

## The inspect screen, opened from party select. This is also where the plan
## editor lives -- issue 53 names it separately but InspectPanel.gd's own
## header comment is explicit there is no separate screen. Pick a pawn with
## real plans (Warrior ships one) and scroll the detail panel so the plan
## row's Condition/Targeting/Action editors are actually on screen, since
## that is where the reported overlap lives.
func _inspect_from_party_select() -> void:
	await _fresh_main()
	if not _press_named("inspect classes"):
		return
	await _settle()
	await _shot("sweep_inspect_default")

	# Select the Warrior specifically -- it ships a real plan with a
	# Condition, a Targeting block and an Action block, which is the row
	# the overlap was found in.
	var inspect_panel = null
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("InspectPanel.gd"):
			inspect_panel = n
			break
	if inspect_panel == null:
		print("ScreenSweep: could not find InspectPanel node")
		return
	for b in _buttons():
		if b.text == "Warrior":
			b.emit_signal("pressed")
			break
	await _settle()

	# Scroll the detail panel to the bottom so the plan row's pickers are in
	# frame -- ScrollContainer under body/detail_scroll per InspectPanel.gd.
	for n in _walk(inspect_panel):
		if n is ScrollContainer:
			n.scroll_vertical = 100000
	await _settle()
	await _shot("sweep_inspect_plan_editor")

## The level editor, reached from party select.
func _level_editor() -> void:
	await _fresh_main()
	if not _press_named("level editor"):
		return
	await _settle()
	await _shot("sweep_level_editor")

## The floor map, reached via Start Run, plus whichever room resolves first.
func _floor_map_and_end_of_fight() -> void:
	await _fresh_main()
	var parties := sweep_parties(Registry.all_class_ids())
	if parties.is_empty() or not _select_classes(parties[0]):
		return
	await get_tree().process_frame

	var run_btn: Button = null
	for b in _buttons():
		if b.text.to_lower().begins_with("start run"):
			run_btn = b
			break
	if run_btn == null:
		print("ScreenSweep: NO 'Start Run' BUTTON FOUND at %s" % _res_tag)
		return
	run_btn.emit_signal("pressed")
	await _settle()
	if _current_screen_name() != "FloorMap":
		print("ScreenSweep: did not reach FloorMap from Start Run at %s" % _res_tag)
		return
	await _shot("sweep_floor_map")
