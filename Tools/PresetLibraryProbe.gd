extends Node

## Issue 412: the library, driven the way a player drives it -- a real
## `InputEventMouseButton` pair at the control's own screen position, pushed
## through Godot's picking, rather than `emit_signal("pressed")` on the button
## the probe found. UnitClickProbe's technique, and it is here for the same
## reason: a signal emitted by hand passes for a control nothing can reach.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""
var _failures := 0

## An abort halfway is a failure, not a pass: every early return above would
## otherwise leave the count at zero.
var _finished := false

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("PresetLibraryProbe: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	_check(_finished, "the probe ran to the end")
	print("PresetLibraryProbe: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("PresetLibraryProbe: %s_%s.png" % [name, _tag])

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

## Every visible Button under `root` whose caption starts with `prefix`.
func _buttons(root: Node, prefix: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in _walk(root):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			out.append(n)
	return out

func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await _settle(2)

## Clicks the control where it is drawn. Refuses rather than clicking a point
## outside the window, which would report as "the control did nothing".
func _click_control(c: Control, what: String) -> bool:
	var rect := c.get_global_rect()
	var at := rect.get_center()
	var window := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	if not window.has_point(at) or rect.size.x < 1.0:
		print("PresetLibraryProbe: %s is at %s, outside the window %s -- not clicking" % [what, rect, window.size])
		_failures += 1
		return false
	await _click(at)
	print("PresetLibraryProbe: clicked %s at %s" % [what, at])
	return true

func _check(ok: bool, message: String) -> void:
	print("PresetLibraryProbe: %s %s" % ["ok  " if ok else "FAIL", message])
	if not ok:
		_failures += 1

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var select := _node_with("PartySelect.gd")
	if select == null:
		_check(false, "no party screen")
		return
	var panel = select._inspect_panel
	var pawn = panel._pawns[0]
	print("PresetLibraryProbe: editing %s (%s)" % [pawn.display_name, pawn.pawn_class.id])

	## The state the ruling left behind: no rows at all.
	_check(pawn.plans.is_empty(), "a starting pawn carries no plan rows")
	_check(panel._library_open, "the library opens on a pawn with no rows")
	await _shot("wren_412_library_open")

	## Closed, which is the empty state a player sees after hiding it: the
	## teaching sentence has to survive it, or there is no way back in.
	var hide_button := _buttons(panel, InspectPanel.LIBRARY_CLOSE)
	_check(hide_button.size() == 1, "one Hide library button, found %d" % hide_button.size())
	if hide_button.is_empty():
		return
	if not await _click_control(hide_button[0], "Hide library"):
		return
	_check(not panel._library_open, "a real click on Hide library closes it")
	_check(_buttons(panel, InspectPanel.LIBRARY_ADD).is_empty(), "and takes the rows off the screen")
	await _shot("wren_412_empty_state")

	var open_button := _buttons(panel, "Library (")
	_check(open_button.size() == 1, "one Library button, found %d" % open_button.size())
	if open_button.is_empty():
		return
	if not await _click_control(open_button[0], open_button[0].text):
		return
	_check(panel._library_open, "a real click on Library opens it again")

	var adds := _buttons(panel, InspectPanel.LIBRARY_ADD)
	_check(adds.size() > 0, "the library offers %d rows" % adds.size())
	if adds.is_empty():
		return
	var before: int = panel._blocks_used(pawn)
	var offered := adds.size()
	if not await _click_control(adds[0], "the first Add"):
		return
	_check(pawn.plans.size() == 1, "a real click on Add put a row on the pawn, size is %d" % pawn.plans.size())
	if pawn.plans.is_empty():
		return
	var added = pawn.plans[0]
	var charged: int = panel._blocks_used(pawn) - before
	_check(charged == added.block_count(),
		"charged %d for a %d-block row" % [charged, added.block_count()])
	_check(_buttons(panel, InspectPanel.LIBRARY_ADD).size() == offered - 1,
		"the taken row left the library")
	print("PresetLibraryProbe: took '%s' (%s)" % [added.display_name, added.id])
	await _shot("wren_412_row_taken")

	await _fight(select, pawn, added)

## And it reaches the simulation. A row accepted, echoed back and absent from
## the event stream is not an edit -- issue 376's own finding.
func _fight(select, pawn, added) -> void:
	## The edited pawn has to be in the party, and the card is how a player puts
	## it there -- "Start Fight" reads "Pick a party to fight" until it is.
	if not await _click_control(select._cards[pawn.id], "the %s card" % pawn.display_name):
		return
	_check(select.selected_pawns().has(pawn), "the edited pawn is in the party")

	var start := _buttons(_main, "start fight")
	if start.is_empty():
		_check(false, "no 'Start Fight' button, found %s" % str(_buttons(_main, "").map(func(b): return b.text)))
		return
	if not await _click_control(start[0], "Start Fight"):
		return
	if _node_with("DeployView.gd") != null:
		var b := _buttons(_main, "start fight")
		if b.is_empty() or not await _click_control(b[0], "start fight (deploy)"):
			return

	var battle = _node_with("BattleView.gd")
	if battle == null:
		_check(false, "no battle screen")
		return
	battle.set_process(false)
	for tick in 600:
		battle._process(CG.TICK_SECONDS)
	await _settle()

	var fired := 0
	for e in battle.state.events:
		if e.source_plan == added.id:
			fired += 1
	_check(fired > 0, "'%s' fired %d times in the fight" % [added.display_name, fired])
	await _shot("wren_412_fight_after_the_row")
	await _wide(battle, pawn)
	_finished = true

## The other screen the library appears on: the full-width Plans panel a player
## opens off a unit card mid-fight, where the row keeps its three columns.
func _wide(battle, pawn) -> void:
	for u in battle.state.units:
		if u.pawn != pawn:
			continue
		await _click(battle._arena.get_global_transform() * BattleView.drawn_position(battle.state, u))
	var plans := _buttons(battle, "plans")
	if plans.is_empty():
		_check(false, "the unit card has no Plans button")
		return
	if not await _click_control(plans[0], "Plans"):
		return
	var panel = battle._inspect_panel
	_check(panel != null and panel.is_visible_in_tree(), "the full-width Plans panel opened")
	if panel == null:
		return
	var open_button := _buttons(panel, "Library (")
	_check(open_button.size() == 1, "the library button is on the wide screen too")
	if open_button.is_empty():
		return
	if not await _click_control(open_button[0], open_button[0].text):
		return
	_check(_buttons(panel, InspectPanel.LIBRARY_ADD).size() > 0, "and it opens there")
	await _shot("wren_412_library_wide")
