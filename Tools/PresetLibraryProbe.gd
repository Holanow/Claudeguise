extends Node

## Issue 412: the library, driven the way a player drives it -- a real
## `InputEventMouseButton` pair at the control's own screen position, pushed
## through Godot's picking, rather than `emit_signal("pressed")` on the button
## the probe found. UnitClickProbe's technique, and it is here for the same
## reason: a signal emitted by hand passes for a control nothing can reach.

const OUT_DIR := "user://probe"

## Issue 520: the gate runs this probe, and the gate runs in the main checkout.
## Set by `gate.ps1` only; a hand run still refuses.
static func gated() -> bool:
	return OS.get_environment("CLAUDEGUISE_GATE") != ""

var _main: Node
var _tag := ""
var _failures := 0

## An abort halfway is a failure, not a pass: every early return above would
## otherwise leave the count at zero.
var _finished := false

func _ready() -> void:
	if not gated() and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
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
	var dir := OUT_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	img.save_png("%s/%s_%s.png" % [dir, name, _tag])
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
	for scroll in _scrolls(c):
		if scroll.get_global_rect().has_point(at):
			continue
		print("PresetLibraryProbe: %s is below the fold of %s (%s vs %s), scrolling to it" % [
			what, scroll.name, rect, scroll.get_global_rect()])
		scroll.ensure_control_visible(c)
		await _settle(2)
		rect = c.get_global_rect()
		at = rect.get_center()
	for scroll in _scrolls(c):
		if scroll.get_global_rect().has_point(at):
			continue
		print("PresetLibraryProbe: %s sits at %s, clipped by %s at %s, and will not scroll into view -- not clicking" % [
			what, rect, scroll.name, scroll.get_global_rect()])
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
	var before: int = panel._rows_used(pawn)
	var offered := adds.size()
	if not await _click_control(adds[0], "the first Add"):
		return
	_check(pawn.plans.size() == 1, "a real click on Add put a row on the pawn, size is %d" % pawn.plans.size())
	if pawn.plans.is_empty():
		return
	var added = pawn.plans[0]
	var charged: int = panel._rows_used(pawn) - before
	_check(charged == 1, "charged %d rows for one row" % charged)
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
	var held = _node_with("BattleView.gd")
	if held != null and held.setup:
		var b := _buttons(_main, "start fight")
		if b.is_empty() or not await _click_control(b[0], "start fight (setup)"):
			return

	var battle = _node_with("BattleView.gd")
	if battle == null:
		_check(false, "no battle screen")
		return
	battle.set_process(false)
	## Issue 842: the roster seed is rolled fresh per launch, so the fight this
	## run measured is only reproducible if the probe says which one it was.
	print("PresetLibraryProbe: seed %s" % battle.config.seed_text())

	## Issue 842: the unit card's route needs the fight still running, so it
	## runs before the ticks that resolve it rather than after them.
	await _unit_card_route(battle, pawn)

	for tick in 600:
		battle._process(CG.TICK_SECONDS)
	await _settle()

	var fired := 0
	for e in battle.state.events:
		if e.source_plan == added.id:
			fired += 1
	_check(fired > 0, "'%s' fired %d times in the fight" % [added.display_name, fired])
	await _shot("wren_412_fight_after_the_row")
	await _end_card_route(battle)
	_finished = true

## Issue 741's narrow tabbed popout, opened off a unit card while the fight is
## still running -- the route this probe is for.
func _unit_card_route(battle, pawn) -> void:
	var unit = null
	for u in battle.state.units:
		if u.pawn == pawn:
			unit = u
	_check(unit != null, "the edited pawn is a unit in the fight")
	if unit == null:
		return
	_check(battle.state.outcome == CombatState.Outcome.UNRESOLVED, "the fight is still running")
	await _click(battle._arena.get_global_transform() * BattleView.drawn_position(battle.state, unit))
	var card = battle._unit_card
	_check(card != null and card.is_visible_in_tree(), "clicking the pawn opened its unit card")
	if card == null or not card.is_visible_in_tree():
		return
	if not await _popout_from(battle, card, "the unit card"):
		return
	await _shot("wren_412_library_mid_fight")
	var esc := _buttons(battle._inspect_panel, "esc")
	_check(esc.size() == 1, "one close button on the popout, found %d" % esc.size())
	if esc.is_empty() or not await _click_control(esc[0], "Esc on the popout"):
		return
	_check(not battle._inspect_panel.is_visible_in_tree(), "Esc closes the popout")
	_check(not battle.paused, "and the fight is running again")

## The other door to the same popout: the end card's own button, once the
## fight is over.
func _end_card_route(battle) -> void:
	var banner = battle._end_banner
	_check(banner != null and banner.is_visible_in_tree(), "the end card is up after the fight")
	if banner == null or not banner.is_visible_in_tree():
		return
	if not await _popout_from(battle, banner, "the end card"):
		return
	await _shot("wren_412_library_wide")

## The popout, opened by `root`'s own Plans button. Issue 842: `root`, not the
## whole battle screen -- three controls open this popout and a search across
## all of them returns whichever tree order happens to put first.
func _popout_from(battle, root: Node, what: String) -> bool:
	var plans := _buttons(root, "plans")
	_check(plans.size() == 1, "one Plans button on %s, found %d" % [what, plans.size()])
	if plans.is_empty():
		return false
	if not await _click_control(plans[0], "Plans on %s" % what):
		return false
	var popout = battle._inspect_panel
	var opened: bool = popout != null and popout.is_visible_in_tree()
	_check(opened, "the Plans & Equipment popout opened from %s" % what)
	if not opened:
		_why_not(battle, plans[0])
		return false
	var open_button := _buttons(popout, "Library (")
	_check(open_button.size() == 1, "the library button is on the popout too")
	if open_button.is_empty():
		return false
	if not await _click_control(open_button[0], open_button[0].text):
		return false
	_check(_buttons(popout, InspectPanel.LIBRARY_ADD).size() > 0, "and it opens there")
	return true

## Issue 842: what stood between the click and the popout, so a failure that
## does not reproduce still explains itself.
func _why_not(battle, button: Control) -> void:
	print("PresetLibraryProbe: outcome=%s paused=%s end_banner=%s pause_menu=%s popout=%s" % [
		battle.state.outcome, battle.paused,
		battle._end_banner != null and battle._end_banner.visible,
		battle._pause_menu != null and battle._pause_menu.visible,
		battle._inspect_panel != null and battle._inspect_panel.visible])
	var at := button.get_global_rect().get_center()
	for n in _walk(_main):
		if n == button or not (n is Control) or not n.is_visible_in_tree():
			continue
		if n.mouse_filter == Control.MOUSE_FILTER_IGNORE or not n.get_global_rect().has_point(at):
			continue
		print("PresetLibraryProbe: over the click at %s: %s" % [at, n.get_path()])
