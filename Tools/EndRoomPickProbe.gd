extends Node

## Issues 590 and 591, measured the way #520 says they have to be: a real
## `InputEventMouseButton` pair at a real screen position for every new
## control, and a real `InputEventMouseMotion` plus
## `Viewport.gui_get_hovered_control()` for every new mouseover.
##
## A hand-emitted `pressed` signal passes on a control eleven pixels under a
## `ScrollContainer`'s clip that no player can ever reach, which is what #520
## was. `gui_get_hovered_control` is the same question asked of a hover.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""
var _failures: Array[String] = []

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("EndRoomPickProbe: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	if _failures.is_empty():
		print("EndRoomPickProbe: %d checks, 0 failures at %s" % [_checks, _tag])
		get_tree().quit(0)
		return
	printerr("EndRoomPickProbe: %d FAILURE(S) at %s:" % [_failures.size(), _tag])
	for f in _failures:
		printerr("  - %s" % f)
	get_tree().quit(1)

var _checks := 0

func _check(ok: bool, what: String) -> bool:
	_checks += 1
	print("EndRoomPickProbe: %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures.append(what)
	return ok

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("EndRoomPickProbe: %s_%s.png" % [name, _tag])

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

## The pointer really moved there, and what the viewport says is under it. A
## tooltip read off a node found by walking the tree proves the string exists;
## this proves the player can reach it.
func _hovered_at(at: Vector2) -> Control:
	var point := get_viewport().get_screen_transform() * at
	var e := InputEventMouseMotion.new()
	e.position = point
	e.global_position = point
	get_viewport().push_input(e)
	await _settle(3)
	return get_viewport().gui_get_hovered_control()

## A hover box really reachable at this point, named. The hovered control or one
## of its ancestors has to be the node we meant AND carry the sentence.
func _check_hover(node: Control, what: String) -> void:
	if node == null or not node.is_visible_in_tree():
		_check(false, "%s: not on the screen at all" % what)
		return
	var box := node.get_global_rect()
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		_check(false, "%s: laid out at zero size, so nothing can point at it" % what)
		return
	var hovered := await _hovered_at(box.get_center())
	_check(hovered == node, "%s: the pointer over it reaches %s" % [
		what, "it" if hovered == node else ("%s (%s)" % [hovered.name, hovered.get_class()]) if hovered != null else "nothing"])
	_check(node.tooltip_text.strip_edges() != "", "%s: carries a sentence" % what)
	if node.has_method("_make_custom_tooltip"):
		_check(node._make_custom_tooltip(node.tooltip_text) != null,
			"%s: builds the game's own hover box rather than the engine's grey one" % what)
	else:
		_check(false, "%s: is not a glossary host" % what)

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
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	## The party that holds a Priest, so the healing column has something in it.
	var party_ids: Array = ScreenSweepScript.sweep_parties(ClassLibrary.all_ids())[-1]
	for id in party_ids:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()

	## Party select first: the equipment icon's mouseover lives here.
	var icon := _node_with("ItemIconView.gd")
	await _shot("heron_591_party_select")
	await _check_hover(icon, "the equipment icon on party select")

	var start := _button("start fight")
	if start == null:
		return null
	await _click(start.get_global_rect().get_center())
	var held = _node_with("BattleView.gd")
	if held != null and held.setup:
		start = _button("start fight")
		if start == null:
			return null
		await _click(start.get_global_rect().get_center())
	return _node_with("BattleView.gd")

## The banner deliberately waits out the freeze frame on the last death, so
## "the outcome is set" and "the end card is up" are two different moments and
## the loop has to be driven past the second one. Breaking at the first is why
## the first run of this probe photographed a finished fight with no card on it.
func _run_out(battle: Node) -> void:
	battle.set_process(false)
	for i in 6000:
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		battle._process(CG.TICK_SECONDS)
	for i in 120:
		if battle._end_banner.visible:
			break
		battle._process(CG.TICK_SECONDS)
	await _settle()

func _run() -> void:
	var battle := await _to_battle()
	if not _check(battle != null, "the battle screen opens"):
		return

	## The What-to-show panel, opened the way a player opens it, then hovered.
	var toggles := _button("what to show")
	if _check(toggles != null, "the What to show button is on the toolbar"):
		await _click(toggles.get_global_rect().get_center())
		await _settle()
		var panel := _node_with("DisplayOptionsPanel.gd")
		await _shot("heron_590_what_to_show")
		if _check(panel != null and panel.visible, "the What to show panel opens"):
			_check(panel.get_combined_minimum_size().y <= get_viewport().get_visible_rect().size.y,
				"the panel fits the window without scrolling to reach a row")
			var rows: Array = panel._rows
			_check(rows.size() == DisplayOptions.OPTIONS.size(), "one row per option")
			## The real click FIRST, before any hover: a tooltip is a separate
			## window and one left standing under the pointer eats the press.
			var before: bool = DisplayOptions.enabled(DisplayOptions.OPTIONS[0].id)
			await _click(rows[0].get_global_rect().get_center())
			_check(DisplayOptions.enabled(DisplayOptions.OPTIONS[0].id) != before,
				"a real click on the row still changes the option")
			await _check_hover(rows[0], "the first What-to-show row")
			## The last row is below the fold and a player scrolls to it, so the
			## probe scrolls to it too -- with the wheel, over the list, which is
			## the gesture. Hovering a clipped row and reporting "unreachable"
			## would be measuring the scrollbar, not the row.
			var last: Control = rows[rows.size() - 1]
			var visible_rows := 0
			for r in rows:
				if panel._scroll.get_global_rect().encloses(r.get_global_rect()):
					visible_rows += 1
			print("EndRoomPickProbe: %d of %d rows are inside the panel without scrolling" % [
				visible_rows, rows.size()])
			await _wheel(panel._scroll.get_global_rect().get_center(), false, 12)
			await _check_hover(last, "the LAST What-to-show row, the one #518 found below the fold")
			await _click(toggles.get_global_rect().get_center())
			await _settle()

	await _run_out(battle)
	if not _check(battle.state.outcome != CombatState.Outcome.UNRESOLVED,
			"the fight resolves, so there is an end card"):
		return
	await _shot("heron_591_end_card")

	## #552 found five layout defects a click probe could not see. Every control
	## the end card owns has to be inside the window, measured rather than
	## eyeballed.
	var window := get_viewport().get_visible_rect()
	print("EndRoomPickProbe: window %s" % window)
	for child in battle._end_banner.get_child(0).get_children():
		print("EndRoomPickProbe:   column child %s %s" % [child.name, child.get_global_rect()])
	## EVERY button on the banner, not only the ones this issue adds. An earlier
	## run of this probe printed the Restart row 21 px past the bottom and called
	## it somebody else's; measured on origin/main it sits at y=669 and fits, so
	## the overflow was the Healed row's and the print was hiding it.
	for n in _walk(battle._end_banner):
		if n is Button and n.is_visible_in_tree():
			_check(window.encloses(n.get_global_rect()),
				"the banner button '%s' is inside the window (%s)" % [n.text, n.get_global_rect()])
	## The prose above the roster is not a fixed height, and the fight this probe
	## happens to get is not the tallest card the game can draw. So it is forced
	## to the worst the game CAN draw -- a casualty list, a reason and a duration,
	## which is three lines -- and every button is checked again. Without it a run
	## only ever sees whichever card that fight happened to produce.
	##
	## Three is also the ceiling, measured: the card clears the bottom by 8 px,
	## and a fourth line puts it 23 px over with the log already on its floor.
	## Reported on #591 rather than paid for by shrinking something else.
	var was: String = battle._end_cost_label.text
	var long_list: Array[String] = []
	for i in 3:
		long_list.append("Four pawns with long names died, and here is the reason why.")
	battle._end_cost_label.text = "\n".join(long_list)
	await _settle(8)
	await _shot("heron_591_end_card_long_prose")
	for n in _walk(battle._end_banner):
		if n is Button and n.is_visible_in_tree():
			_check(window.encloses(n.get_global_rect()),
				"with a card too tall to fit, '%s' is still inside the window (%s)" % [
					n.text, n.get_global_rect()])
	var squeezed: float = battle._end_screen._log_side.size.y
	print("EndRoomPickProbe: the log is %.0f px under a card too tall to fit" % squeezed)
	battle._end_cost_label.text = was
	await _settle(8)
	var roomy: float = battle._end_screen._log_side.size.y
	print("EndRoomPickProbe: and %.0f px once the prose is short again" % roomy)
	_check(squeezed < roomy, "the log is what gave way, and it comes back")
	_check(squeezed >= EndScreen.LOG_MIN_HEIGHT,
		"the log shrank past a caption and one line")

	## The healing column is on the card, not only in the tally.
	var text := _text_of(battle._end_screen)
	_check(text.contains("Healed"), "the end card names damage healed: %s" % text.substr(0, 200))
	_check(text.contains("Damage healed"), "and it is a sort of its own")

	## A portrait, hovered.
	var portraits: Array[Control] = []
	for n in _walk(battle._end_screen):
		if (n is TextureRect or n is ColorRect) and n.tooltip_text != "":
			portraits.append(n)
	if _check(not portraits.is_empty(), "the roster draws portraits that carry a sentence"):
		await _check_hover(portraits[0], "the first end-card portrait")

	## Sorting by healed, through a real press.
	var sort := _sort_button(battle, "SortByHealed")
	if _check(sort != null, "the healed sort control is on the screen"):
		await _click(sort.get_global_rect().get_center())
		_check(battle._end_screen.sort_by() == 2, "a real click sorts by healing")
		await _shot("heron_591_end_card_sorted_by_healed")

	## And the room picker, pressed for real.
	_check(battle._room_buttons.size() == RoomLibrary.pickable_ids().size(),
		"one room button per pickable room, %d of %d" % [
			battle._room_buttons.size(), RoomLibrary.pickable_ids().size()])
	var here: StringName = battle.config.encounter_id
	var want: Button = null
	var want_id: StringName = &""
	for id in battle._room_buttons:
		if id != here:
			want = battle._room_buttons[id]
			want_id = id
			break
	if not _check(want != null, "a room other than the current one is offered"):
		return
	await _check_hover(want, "the room button '%s'" % want.text)
	await _click(want.get_global_rect().get_center())
	await _settle(10)
	var next = _node_with("BattleView.gd")
	_check(next != null and next != battle,
		"a real click on a room button opens a new fight")
	if next != null:
		_check(next.config != null and next.config.encounter_id == want_id,
			"and it is the room that was pressed: asked %s, got %s" % [
				want_id, "nothing" if next.config == null else next.config.encounter_id])
	await _shot("heron_591_new_room")

func _sort_button(battle: Node, node_name: String) -> Button:
	for n in _walk(battle):
		if n is Button and n.name == node_name:
			return n
	return null

func _text_of(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + " "
	if node is Button:
		out += node.text + " "
	for child in node.get_children():
		out += _text_of(child)
	return out
