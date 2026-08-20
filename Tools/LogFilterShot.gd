extends Node

## Issue 319: the middle of the Burn Pit with the ground switched on and then
## off, at the same tick of the same fight. The window a blind playtester lost.

const OUT_DIR := "res://Screenshots"
const STOP_TICK := 88

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("LogFilterShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("LogFilterShot: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	print("LogFilterShot: no visible button '%s'" % prefix)
	return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _select_room(picker: OptionButton, want: String) -> bool:
	for i in picker.item_count:
		if String(picker.get_item_metadata(i)).contains(want):
			picker.selected = i
			picker.item_selected.emit(i)
			return true
	print("LogFilterShot: the picker offers no room matching '%s'" % want)
	return false

## The lines a player can actually see, which is the only part of the log this
## issue is about.
func _tail(log_view: Node, n: int) -> PackedStringArray:
	var lines: PackedStringArray = log_view._label.get_parsed_text().split("\n")
	return lines.slice(maxi(0, lines.size() - n))

func _run() -> bool:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var select := _node_with("PartySelect.gd")
	var cards: Array[Node] = []
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			cards.append(n)
	for i in mini(4, cards.size()):
		cards[i].toggled.emit(true)
	await _settle()
	if not _select_room(select._room_picker, "hazard"):
		return false
	select._seed_edit.text = "00000001"
	await _settle()
	if not _press("start fight"):
		return false
	await _settle()
	if _node_with("DeployView.gd") != null:
		if not _press("start fight"):
			return false
		await _settle()

	var battle := _node_with("BattleView.gd")
	if battle == null:
		print("LogFilterShot: no battle screen")
		return false

	## One tick per call, through the screen's own frame handler, with the
	## engine's own _process off so nothing else advances the fight.
	battle.set_process(false)
	var log_view := _node_with("CombatLogView.gd")
	## SHOT_TICK overrides the stop, so the worst tick this prints can be handed
	## straight back to a second run.
	var stop := int(OS.get_environment("SHOT_TICK")) if OS.get_environment("SHOT_TICK") != "" else STOP_TICK
	var worst := 0
	var worst_tick := 0
	## Stepped to a tick number rather than for a count of steps: a few ticks
	## already went by at frame rate before the fight could be taken off
	## _process, and two runs must land on the same tick to be comparable.
	while battle.state.tick < stop:
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		battle._process(CG.TICK_SECONDS)
		var ground := 0
		for l in _tail(log_view, 8):
			if l.contains("from the ground"):
				ground += 1
		if ground > worst:
			worst = ground
			worst_tick = battle.state.tick
	print("LogFilterShot: worst visible window is tick %d, %d of 8 lines from the ground" % [
		worst_tick, worst])
	await _settle()

	print("LogFilterShot: tick %d, %d lines in the log. The last of them:" % [
		battle.state.tick, log_view._label.get_parsed_text().split("\n").size()])
	for l in _tail(log_view, 9):
		print("LogFilterShot:   %s" % l)
	await _shot("wren_log_ground_on")

	## Now the switch, through the panel a player opens.
	if not _press("what to show"):
		return false
	await _settle()
	var panel := _node_with("DisplayOptionsPanel.gd")
	for box in panel._rows:
		if box.text.begins_with("Ground damage in the log"):
			await _click(box.get_global_rect().get_center())
	await _settle()
	await _shot("wren_log_filter_panel")
	if not _press("what to show"):
		return false
	await _settle()
	print("LogFilterShot: with the ground switched off, %d lines. The last of them:" % [
		log_view._label.get_parsed_text().split("
").size()])
	for l in _tail(log_view, 9):
		print("LogFilterShot:   %s" % l)
	await _shot("wren_log_ground_off")
	return true

## A real click at a real place, both halves, since a Button acts on release.
## `at` is a control rect, which is in viewport space; the window stretches
## ("canvas_items", "expand"), so an event carrying viewport coordinates lands
## somewhere else at any size but 1280x720. Measured: the same click that works
## at 1280x720 misses entirely at 844x390.
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
