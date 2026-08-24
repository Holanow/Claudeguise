extends Node

## Issue 552: the post-fight roster, driven the way a player drives it -- a real
## `InputEventMouseButton` pair at the control's own screen position, pushed
## through Godot's picking, rather than `emit_signal("pressed")` on the button
## the probe found.
##
## Issue 520 is why: a control 11 px under a `ScrollContainer`'s clip took no
## input at all, and a hand-emitted signal would have passed happily. **A sort
## button below the fold fails this probe rather than being scrolled past.**

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const EndScreenScript := preload("res://Scripts/UI/EndScreen.gd")
const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""
var _failures := 0

## An abort halfway is a failure, not a pass.
var _finished := false

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("EndRosterProbe: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	_check(_finished, "the probe ran to the end")
	print("EndRosterProbe: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("EndRosterProbe: %s_%s.png" % [name, _tag])

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

func _button(prefix: String) -> Button:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			return n
	return null

func _check(ok: bool, message: String) -> void:
	print("EndRosterProbe: %s %s" % ["ok  " if ok else "FAIL", message])
	if not ok:
		_failures += 1

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

## Every `ScrollContainer` above this control. Issue 520: a scroll clips input
## as well as pixels, so a control below the fold gets no event and reads as
## inert whatever the screenshot shows.
func _scrolls(c: Control) -> Array[ScrollContainer]:
	var out: Array[ScrollContainer] = []
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			out.append(n)
		n = n.get_parent()
	return out

## Clicks the control where it is drawn, and **refuses rather than scrolling to
## it**. A sort control the player has to find is the defect this probe exists
## to catch, so reaching it by scrolling would be the probe passing itself.
func _click_control(c: Control, what: String) -> bool:
	var rect := c.get_global_rect()
	var at := rect.get_center()
	var window := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	if not window.has_point(at) or rect.size.x < 1.0:
		_check(false, "%s is at %s, outside the window %s" % [what, rect, window.size])
		return false
	for scroll in _scrolls(c):
		if not scroll.get_global_rect().has_point(at):
			_check(false, "%s sits at %s, clipped by %s at %s -- a sort control below the fold takes no input" % [
				what, rect, scroll.name, scroll.get_global_rect()])
			return false
	var reached := _topmost_at(at)
	if not (reached is Button):
		_check(false, "%s is covered: a click at %s reaches %s" % [what, at, reached.name if reached != null else "nothing"])
		return false
	await _click(at)
	print("EndRosterProbe: clicked %s at %s" % [what, at])
	return true

## What a click at this point would land on, in the order the viewport tries
## them: last sibling wins.
func _topmost_at(point: Vector2) -> Control:
	var hit: Control = null
	for n in _walk(_main):
		if n is Control and n.is_visible_in_tree() \
				and n.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and n.get_global_rect().has_point(point):
			hit = n
	return hit

func _to_battle() -> Node:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	## The Siege Master is in this party on purpose: it is the one class that
	## builds a summon, so the roster's summon attribution is exercised for real
	## rather than only against a hand-built event stream.
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	for id in [&"siege_master", &"warrior", &"priest", &"geysermancer"]:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()
	var start := _button("start fight")
	if start == null:
		return null
	start.emit_signal("pressed")
	await _settle()
	var held = _node_with("BattleView.gd")
	if held != null and held.setup:
		start = _button("start fight")
		if start == null:
			return null
		start.emit_signal("pressed")
		await _settle()
	return _node_with("BattleView.gd")

func _order(screen) -> Array:
	var out: Array = []
	for row in screen.shown_rows():
		out.append("%s d%d t%d" % [row["name"], int(row["dealt"]), int(row["taken"])])
	return out

## True when the cards on screen run highest-first down `key`.
func _is_ordered_by(screen, key: String) -> bool:
	var last := 1 << 30
	for row in screen.shown_rows():
		var v := int(row[key])
		if v > last:
			return false
		last = v
	return true

func _run() -> void:
	var battle := await _to_battle()
	if battle == null:
		_check(false, "never reached the battle screen")
		return
	battle.set_process(false)
	for i in 6000:
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		battle._process(CG.TICK_SECONDS)
	if battle.state.outcome == CombatState.Outcome.UNRESOLVED:
		_check(false, "the fight never resolved, so there is no roster to probe")
		return
	## The banner waits out the hit-stop freeze on the last death, so resolving
	## the fight is not the same as showing the screen. Pumped rather than
	## assumed: stopping at the outcome leaves the roster unbuilt and every check
	## below reads a screen the player never sees.
	var waited := 0
	while not battle._end_banner.visible and waited < 600:
		battle._process(CG.TICK_SECONDS)
		waited += 1
	_check(battle._end_banner.visible, "the end banner is up after %d frames of hit-stop" % waited)
	await _settle()
	print("EndRosterProbe: outcome %s at tick %d" % [
		CombatState.Outcome.keys()[battle.state.outcome], battle.state.tick])

	var screen = battle._end_screen
	_check(screen != null and screen.is_visible_in_tree(), "the roster is on screen after the fight")
	if screen == null:
		return

	_check(screen._roster.get_child_count() > 0, "the roster has %d cards" % screen._roster.get_child_count())
	print("EndRosterProbe: by dealt   %s" % [_order(screen)])
	await _shot("teal_552_roster_by_dealt")

	## The log is the player's other ask, and an empty one would pass every
	## structural check silently.
	_check(screen._log_label.text.length() > 0, "the full log is not empty")
	var log_lines: int = screen._log_label.text.split("\n").size()
	_check(log_lines > 20, "the full log carries %d lines" % log_lines)

	var taken_button: Button = screen._sort_buttons[EndScreenScript.SortBy.TAKEN]
	var dealt_button: Button = screen._sort_buttons[EndScreenScript.SortBy.DEALT]
	_check(dealt_button.button_pressed, "the active sort is marked on the control before anything is clicked")

	## Not "the order changed": on a fight where one pawn leads both columns the
	## two orders are legitimately identical, and asserting a difference would
	## make this probe's verdict depend on the seed. The column is checked for
	## being ordered instead, which is true of every fight.
	_check(_is_ordered_by(screen, "dealt"), "the roster is ordered by damage dealt")
	if await _click_control(taken_button, "the Damage taken sort"):
		_check(screen.sort_by() == EndScreenScript.SortBy.TAKEN,
			"a real click on Damage taken changed the sort")
		_check(taken_button.button_pressed and not dealt_button.button_pressed,
			"the active sort must be visible on the control, not only in the order")
		_check(_is_ordered_by(screen, "taken"), "the roster is ordered by damage taken")
		print("EndRosterProbe: by taken   %s" % [_order(screen)])
		await _shot("teal_552_roster_by_taken")

	if await _click_control(dealt_button, "the Damage dealt sort"):
		_check(screen.sort_by() == EndScreenScript.SortBy.DEALT, "and back again")
		_check(_is_ordered_by(screen, "dealt"), "and ordered by damage dealt again")

	## Issue 343's claim, re-checked because this screen is what would break it:
	## the toolbar is still alive under the roster.
	for name in ["Pause", "Restart", "Change party", "Plans"]:
		var b := _button(name)
		if b == null:
			_check(false, "no visible button '%s' after the fight" % name)
			continue
		var reached := _topmost_at(b.get_global_rect().get_center())
		_check(reached == b, "'%s' still takes its own clicks, not %s" % [
			name, reached.name if reached != null else "nothing"])

	_finished = true
