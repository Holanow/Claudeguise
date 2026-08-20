extends Node

## Issue 343. Three claims from a blind playtester, each of which is either
## true or not: the log will not scroll, the Victory overlay dims it, and the
## whole toolbar is dead after the fight ends. Measured the way TogglesProbe
## measures a checkbox -- a real InputEvent at a real screen position, and a
## report of what the viewport would actually hand it to.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""
var _failures := 0

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("EndScreenProbe: refusing to run in the main checkout -- use a worktree.")
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
	print("EndScreenProbe: %s_%s.png" % [name, _tag])

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

## What a click at this point would land on, walked in the order the viewport
## tries them: last sibling first, so the last match wins.
func _topmost_at(point: Vector2) -> String:
	var hit := "nothing"
	for n in _walk(_main):
		if n is Control and n.is_visible_in_tree() \
				and n.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and n.get_global_rect().has_point(point):
			hit = "%s (%s)" % [n.name, n.get_class()]
	return hit

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

func _wheel(at: Vector2, up: bool, times: int = 4) -> void:
	var point := get_viewport().get_screen_transform() * at
	for i in times:
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
			e.pressed = pressed
			e.factor = 1.0
			e.position = point
			e.global_position = point
			get_viewport().push_input(e)
		await _settle(2)

func _to_battle() -> Node:
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
	var start := _button("start fight")
	if start == null:
		return null
	start.emit_signal("pressed")
	await _settle()
	if _node_with("DeployView.gd") != null:
		start = _button("start fight")
		if start == null:
			return null
		start.emit_signal("pressed")
		await _settle()
	return _node_with("BattleView.gd")

## The wheel over the log, and whether the scrollbar moved. Reported both ways
## round: a log that cannot scroll up is the defect, and a log that will not
## come back down would be a defect I introduced.
func _measure_scroll(log_view: Node, when: String) -> void:
	var bar: VScrollBar = log_view._label.get_v_scroll_bar()
	var box: Rect2 = log_view._label.get_global_rect()
	var at := box.get_center()
	print("EndScreenProbe: [%s] log box %s, scroll value=%.1f page=%.1f max=%.1f, topmost at centre = %s" % [
		when, box, bar.value, bar.page, bar.max_value, _topmost_at(at)])
	if bar.max_value <= bar.page:
		print("EndScreenProbe: [%s] the log has nothing to scroll -- not a measurement" % when)
		return
	var before := bar.value
	await _wheel(at, true)
	var after := bar.value
	print("EndScreenProbe: [%s] wheel up: %.1f -> %.1f" % [when, before, after])
	if after >= before:
		print("EndScreenProbe: [%s] FAIL the log did not scroll up" % when)
		_failures += 1
	await _wheel(at, false, 8)
	print("EndScreenProbe: [%s] wheel down: %.1f -> %.1f" % [when, after, bar.get_value()])

## Scroll up, then let one more line arrive. `scroll_following` snaps a
## RichTextLabel to the bottom on every append, so a log that answers the wheel
## can still be unreadable during a fight -- which is what the issue describes
## and what the wheel measurement above cannot see with the fight held.
func _measure_follow(battle: Node, log_view: Node) -> void:
	var bar: VScrollBar = log_view._label.get_v_scroll_bar()
	if bar.max_value <= bar.page:
		return
	await _wheel(log_view._label.get_global_rect().get_center(), true, 6)
	var scrolled_to := bar.value
	for i in 30:
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		battle._process(CG.TICK_SECONDS)
	await _settle()
	print("EndScreenProbe: [mid-fight] scrolled to %.1f, then 30 ticks of new lines left it at %.1f (bottom is %.1f)" % [
		scrolled_to, bar.value, bar.max_value - bar.page])
	if bar.value >= bar.max_value - bar.page - 1.0 and scrolled_to < bar.max_value - bar.page - 1.0:
		print("EndScreenProbe: FAIL a new log line yanked the reader back to the bottom")
		_failures += 1

func _run() -> bool:
	var battle := await _to_battle()
	if battle == null:
		print("EndScreenProbe: never reached the battle screen")
		return false
	var log_view := _node_with("CombatLogView.gd")

	## Mid-fight, with the fight held so the measurement is repeatable.
	battle.set_process(false)
	for i in 200:
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		battle._process(CG.TICK_SECONDS)
	await _settle()
	await _shot("wren_endscreen_midfight")
	await _measure_scroll(log_view, "mid-fight")
	await _measure_follow(battle, log_view)

	## Then run it out. `_process` is off, so the outcome has to be stepped to.
	for i in 4000:
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		battle._process(CG.TICK_SECONDS)
	if battle.state.outcome == CombatState.Outcome.UNRESOLVED:
		print("EndScreenProbe: the fight never resolved, so there is no end screen to probe")
		return false
	await _settle()
	await _shot("wren_endscreen_victory")
	print("EndScreenProbe: outcome %s at tick %d" % [
		CombatState.Outcome.keys()[battle.state.outcome], battle.state.tick])

	## Every toolbar control, by what a click on it would reach.
	for name in ["Pause", "Restart", "Change party", "What to show", "Plans"]:
		var b := _button(name)
		if b == null:
			print("EndScreenProbe: FAIL no visible button '%s' after the fight" % name)
			_failures += 1
			continue
		var reach := _topmost_at(b.get_global_rect().get_center())
		var reachable := reach.begins_with(b.name) or reach.contains("Button")
		print("EndScreenProbe: '%s' at %s -> a click reaches %s%s" % [
			b.text, b.get_global_rect().get_center(), reach, "" if reachable else "   <-- BLOCKED"])
		if not reachable:
			_failures += 1

	## And the one that matters most: Plans, pressed the way a player presses it.
	var plans := _button("Plans")
	var panel := _node_with("InspectPanel.gd")
	if plans != null and panel != null:
		await _click(plans.get_global_rect().get_center())
		print("EndScreenProbe: after clicking Plans, the inspect panel is visible=%s" % panel.visible)
		if not panel.visible:
			print("EndScreenProbe: FAIL Plans is dead on the end screen")
			_failures += 1
		await _shot("wren_endscreen_plans")
		if panel.visible:
			panel.close()
			await _settle()

	await _measure_scroll(log_view, "after victory")
	print("EndScreenProbe: %d failure(s)" % _failures)
	return _failures == 0
