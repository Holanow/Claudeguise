extends Node

## Issue 323: a blind playtester clicked both "What to show" toggles and
## neither took. This clicks them the way a mouse does -- a real
## InputEventMouseButton at a real screen position, pushed into the viewport --
## rather than calling the signal underneath.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("TogglesProbe: refusing to run in the main checkout -- use a worktree.")
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
	print("TogglesProbe: %s_%s.png" % [name, _tag])

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
	print("TogglesProbe: no visible button '%s'" % prefix)
	return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

## Scrolls the panel's list until the row is inside its window, which is what a
## player does to reach a row below the fold.
func _reveal(panel: Node, box: Control) -> void:
	if panel._scroll == null:
		return
	panel._scroll.ensure_control_visible(box)
	await _settle(2)

## A real click at a real place. Both halves of the press, and a frame between
## them, because a Button acts on the release.
func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await _settle(2)

func _run() -> bool:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	## By the card's own `class_def`, never by index: the first four cards of an
	## alphabetical roster are never a Warrior (#350). The partition's last
	## party holds the classes a prefix never reached.
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	var party_ids: Array = ScreenSweepScript.sweep_parties(Registry.all_class_ids())[-1]
	for id in party_ids:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()
	if not _press("start fight"):
		return false
	await _settle()
	## The battle screen opens held before its first tick with the party
	## draggable, and its own button carries the same words.
	var held = _node_with("BattleView.gd")
	if held != null and held.setup:
		if not _press("start fight"):
			return false
		await _settle()

	var battle := _node_with("BattleView.gd")
	if battle == null:
		print("TogglesProbe: no battle screen")
		return false
	battle.set_process(false)

	## Through the button a player presses, not through toggle_visible().
	if not _press("what to show"):
		return false
	await _settle()

	var panel := _node_with("DisplayOptionsPanel.gd")
	print("TogglesProbe: panel visible=%s rect=%s" % [panel.visible, panel.get_global_rect()])
	await _shot("wren_toggles_open")

	var failures := 0
	for box in panel._rows:
		var id: StringName = &""
		for option in DisplayOptions.OPTIONS:
			if box.text.begins_with(option.label):
				id = option.id
		var before := DisplayOptions.enabled(id)

		## Scroll it into view first. The panel is a scrolling list and the last
		## two rows sit below its window, so `get_global_rect()` gave a layout
		## position off the bottom of the screen and six clicks landed on
		## nothing -- the probe's own blindness, not a dead checkbox (#373).
		await _reveal(panel, box)
		var rect: Rect2 = box.get_global_rect()

		## Three places a player would aim: the box itself, the words, and the
		## empty space to the right of them on the same row.
		for spot in [
				Vector2(rect.position.x + 8.0, rect.get_center().y),
				Vector2(rect.get_center().x, rect.get_center().y),
				Vector2(rect.end.x - 8.0, rect.get_center().y)]:
			DisplayOptions.set_enabled(id, before)
			panel.refresh()
			await _settle(2)
			var on_top := _topmost_at(spot)
			await _click(spot)
			var took := DisplayOptions.enabled(id) != before
			print("TogglesProbe: %-26s at %s  rect=%s  took=%s  topmost=%s" % [
				box.text, spot, rect, took, on_top])
			if not took:
				failures += 1
		DisplayOptions.set_enabled(id, before)
	print("TogglesProbe: %d click(s) did nothing" % failures)

	## And the thing the player was actually trying to do: turn the plates on,
	## close the panel, and see names over the units.
	## Back in step with the values the loop above kept restoring, or a box that
	## still looks pressed gets skipped and the capture is of nothing changing.
	panel.refresh()
	await _settle(2)
	for box in panel._rows:
		if not box.button_pressed:
			await _reveal(panel, box)
			await _click(box.get_global_rect().get_center())
	await _settle()
	await _shot("wren_toggles_on")
	if not _press("what to show"):
		return false
	for tick in 60:
		battle._process(CG.TICK_SECONDS)
	await _settle()
	await _shot("wren_toggles_plates_on")
	return failures == 0

## What a click at this point would actually land on, walked in the order the
## viewport tries them: last sibling first.
func _topmost_at(point: Vector2) -> String:
	var hit := ""
	for n in _walk(_main):
		if n is Control and n.is_visible_in_tree() \
				and n.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and n.get_global_rect().has_point(point):
			hit = "%s (%s)" % [n.name, n.get_class()]
	return hit
