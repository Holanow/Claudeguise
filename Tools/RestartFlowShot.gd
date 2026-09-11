extends Node

## Issue 840, driven the way a player drives it: take a fight to its end card,
## press Restart, and read what the party screen comes back holding. Then type
## the first fight's seed back in, to show same-seed retry survives as
## read-then-type rather than as a button.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "user://probe"

var _main: Node
var _tag := ""
var _failures := 0

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("RestartFlowShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	print("RestartFlowShot: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("RestartFlowShot: %s_%s.png" % [name, _tag])

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

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _click(at: Vector2) -> void:
	var point := get_viewport().get_screen_transform() * at
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = point
		e.global_position = point
		get_viewport().push_input(e)
		await _settle(2)

func _escape() -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_ESCAPE
		e.pressed = pressed
		get_viewport().push_input(e)
	await _settle()

func _check(ok: bool, message: String) -> void:
	print("RestartFlowShot: %s %s" % ["ok  " if ok else "FAIL", message])
	if not ok:
		_failures += 1

## A click, not `emit_signal`: a control the player cannot reach is issue 520's
## whole defect and a signal would hide it.
func _press(prefix: String) -> bool:
	var b := _button(prefix)
	if b == null:
		_check(false, "no visible button starting '%s'" % prefix)
		return false
	var rect := b.get_global_rect()
	var window := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	if not window.has_point(rect.get_center()):
		_check(false, "'%s' is at %s, outside %s" % [b.text, rect, window.size])
		return false
	await _click(rect.get_center())
	return true

func _pick_a_party() -> void:
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	for id in ScreenSweepScript.sweep_parties(ClassLibrary.all_ids())[-1]:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()

## Start Fight twice: the first opens the battle screen held for placement.
func _start_fight() -> Node:
	if not await _press("start fight"):
		return null
	var held := _node_with("BattleView.gd")
	if held != null and held.setup:
		if not await _press("start fight"):
			return null
	return _node_with("BattleView.gd")

## Past the outcome, not up to it: the banner waits out the freeze on the last
## death, so a loop that stops the tick the fight resolves never sees the card.
func _run_to_the_end(battle: Node) -> String:
	battle.set_process(false)
	var mark := ""
	for i in 6000:
		battle._process(CG.TICK_SECONDS)
		if mark == "" and battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			mark = _fingerprint(battle)
		if battle._end_banner != null and battle._end_banner.visible:
			break
	await _settle()
	if battle._end_banner == null or not battle._end_banner.visible:
		return ""
	return mark

func _fingerprint(battle: Node) -> String:
	return "%s at tick %d, %d events" % [
		CombatState.Outcome.keys()[battle.state.outcome], battle.state.tick,
		battle.state.events.size()]

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	await _pick_a_party()

	var battle := await _start_fight()
	if battle == null:
		_check(false, "the fight never started")
		return
	var first_seed: String = _main.run_config.seed_text()

	## The Escape menu, mid-fight, because the end card suppresses it.
	await _escape()
	_check(battle._pause_menu.visible, "Escape opened the pause menu")
	print("RestartFlowShot: the Escape menu offers %s" % [battle._pause_menu.button_labels()])
	_check(not ("Change party" in battle._pause_menu.button_labels()),
		"no Change party button in the Escape menu")
	await _shot("wren2_840_escape_menu")
	await _escape()
	_check(not battle._pause_menu.visible, "Escape closed it again")

	var first := await _run_to_the_end(battle)
	if first == "":
		_check(false, "the fight never resolved, so there is no end card")
		return
	print("RestartFlowShot: fight 1 seed %s -- %s" % [first_seed, first])
	await _shot("wren2_840_end_card")

	_check(_button("change party") == null, "no Change party button on the end card")
	_check(_button("restart") != null, "the end card offers Restart")

	if not await _press("restart"):
		return
	var select := _node_with("PartySelect.gd")
	_check(select != null, "Restart opened the party screen")
	if select == null:
		return
	var rolled: String = _main.run_config.seed_text()
	var in_field: String = select.current_config().seed_text()
	_check(rolled != first_seed, "Restart rolled a new seed: %s -> %s" % [first_seed, rolled])
	_check(in_field == rolled, "the seed field shows the rolled seed (%s)" % in_field)
	_check(select.selected_pawns().size() > 0, "the party came back picked")
	await _shot("wren2_840_restart_opens_party_select")

	var second := await _start_fight()
	if second == null:
		return
	var second_mark := await _run_to_the_end(second)
	if second_mark == "":
		_check(false, "the second fight never resolved")
		return
	print("RestartFlowShot: fight 2 seed %s -- %s" % [rolled, second_mark])
	_check(second_mark != first, "the new seed produced a different fight")
	await _shot("wren2_840_new_seed_fight")

	## Same-seed retry, the way it survives issue 840: read the seed off the
	## screen, press Restart, type it back, and start.
	if not await _press("restart"):
		return
	var again := _node_with("PartySelect.gd")
	if again == null:
		_check(false, "the second Restart did not reach the party screen")
		return
	## `prefill_seed` only fills the seed field: the pawns fought again are the
	## ones `Main` handed back through `restore_roster`.
	again.prefill_seed(first_seed)
	await _settle()
	_check(again._seed_edit.text == first_seed,
		"the field shows the typed seed (%s)" % again._seed_edit.text)
	await _shot("wren2_840_same_seed_typed_back")
	var retry := await _start_fight()
	if retry == null:
		return
	var retry_mark := await _run_to_the_end(retry)
	if retry_mark == "":
		_check(false, "the retry never resolved")
		return
	print("RestartFlowShot: retry seed %s -- %s" % [
		_main.run_config.seed_text(), retry_mark])
	_check(_main.run_config.seed_text() == first_seed,
		"the typed seed is the one the fight ran on")
	_check(retry_mark == first,
		"typing the seed back reproduced fight 1 exactly")
