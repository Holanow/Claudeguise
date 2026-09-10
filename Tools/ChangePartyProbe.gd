extends Node

## Issue 380, driven the way a player drives it: write a plan row on the party
## screen with a real click, take the fight, go back to the party screen, and
## read the row back. The playtester built the Warrior's four rows three
## separate times because this path threw them away.
##
## Issue 840 made Restart the only control that leaves a fight, so the way back
## is Escape and then the menu's Restart.

const OUT_DIR := "user://probe"

var _main: Node
var _tag := ""
var _failures := 0
var _finished := false

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ChangePartyProbe: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	_check(_finished, "the probe ran to the end")
	print("ChangePartyProbe: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("ChangePartyProbe: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	if not is_instance_valid(n) or n.is_queued_for_deletion():
		return []
	var out: Array[Node] = [n]
	for c in n.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			out.append_array(_walk(c))
	return out

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if is_instance_valid(n) and n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _buttons(root: Node, prefix: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in _walk(root):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			out.append(n)
	return out

## A real key. Escape is what opens the menu #825 moved these controls into.
func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		get_viewport().push_input(e)
		await _settle(2)

func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await _settle(2)

## Issue 520: a ScrollContainer clips input as well as pixels, so a control
## below the fold gets no event and reads as inert.
func _scrolls(c: Control) -> Array[ScrollContainer]:
	var out: Array[ScrollContainer] = []
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			out.append(n)
		n = n.get_parent()
	return out

func _click_control(c: Control, what: String) -> bool:
	var rect := c.get_global_rect()
	var at := rect.get_center()
	var window := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	if not window.has_point(at) or rect.size.x < 1.0:
		print("ChangePartyProbe: %s is at %s, outside %s -- not clicking" % [what, rect, window.size])
		_failures += 1
		return false
	for scroll in _scrolls(c):
		if scroll.get_global_rect().has_point(at):
			continue
		print("ChangePartyProbe: %s is below the fold of %s (%s vs %s), scrolling to it" % [
			what, scroll.name, rect, scroll.get_global_rect()])
		scroll.ensure_control_visible(c)
		await _settle(2)
		rect = c.get_global_rect()
		at = rect.get_center()
	for scroll in _scrolls(c):
		if scroll.get_global_rect().has_point(at):
			continue
		print("ChangePartyProbe: %s sits at %s, clipped by %s at %s, and will not scroll into view -- not clicking" % [
			what, rect, scroll.name, scroll.get_global_rect()])
		_failures += 1
		return false
	await _click(at)
	print("ChangePartyProbe: clicked %s at %s" % [what, at])
	return true

func _check(ok: bool, message: String) -> bool:
	print("ChangePartyProbe: %s %s" % ["ok  " if ok else "FAIL", message])
	if not ok:
		_failures += 1
	return ok

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var select := _node_with("PartySelect.gd")
	if select == null:
		_check(false, "no party screen")
		return
	var panel = select._inspect_panel
	var pawn: PawnData = panel._pawns[0]
	print("ChangePartyProbe: editing %s" % pawn.display_name)

	var adds := _buttons(panel, InspectPanel.LIBRARY_ADD)
	if adds.is_empty():
		_check(false, "no Add button in the library")
		return
	if not await _click_control(adds[0], "the library's first Add"):
		return
	_check(pawn.plans.size() == 1, "one row written, got %d" % pawn.plans.size())
	var written: StringName = pawn.plans[0].id if not pawn.plans.is_empty() else &""

	## A second room, chosen the way the dropdown chooses one.
	var room: StringName = &""
	for id in PartySelect.offered_rooms():
		if id != CG.DEFAULT_ENCOUNTER:
			room = id
			break
	if room != &"":
		for i in select._room_picker.item_count:
			if select._room_picker.get_item_metadata(i) == room:
				select._room_picker.selected = i
				select._room_picker.item_selected.emit(i)
				break

	for card in _walk(select):
		if card.get_script() != null and card.get_script().resource_path.ends_with("PartyCard.gd") \
			and card.class_def != null and card.class_def.id == pawn.pawn_class.id:
			if not await _click_control(card, "the %s card" % pawn.display_name):
				return
			break
	_check(select.selected_pawns().size() == 1, "one pawn picked")
	await _shot("wren_380_authored")

	for step in 2:
		var start := _buttons(_main, "start fight")
		if start.is_empty():
			_check(false, "no Start Fight button at step %d" % step)
			return
		if not await _click_control(start[0], "Start Fight"):
			return
	var battle := _node_with("BattleView.gd")
	if battle == null:
		_check(false, "the fight never started")
		return

	await _key(KEY_ESCAPE)
	if not _check(battle._pause_menu.visible, "Escape opens the pause menu"):
		return
	var back := _buttons(battle._pause_menu, "restart")
	if back.is_empty():
		_check(false, "no Restart button on the Escape menu")
		return
	if not await _click_control(back[0], "Restart"):
		return

	var again := _node_with("PartySelect.gd")
	if again == null:
		_check(false, "Restart did not return to the party screen")
		return
	var back_pawn: PawnData = again.available_pawns()[0]
	_check(back_pawn == pawn, "the same pawn object came back")
	_check(back_pawn.plans.size() == 1 and back_pawn.plans[0].id == written,
		"the authored row survived: %d row(s)" % back_pawn.plans.size())
	_check(again.selected_pawns().size() == 1, "the party came back picked")
	if room != &"":
		_check(again.selected_room() == room,
			"the room came back as %s, wanted %s" % [again.selected_room(), room])
	await _shot("wren_380_after_restart")
	_finished = true
