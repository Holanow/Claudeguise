extends Node

## Issue 449. Hovers with real `InputEventMouseMotion` pushed through Godot's own
## picking, the way `Tools/UnitClickProbe.gd` clicks.
##
## The engine's own tooltip popup never appears under a pushed event in this
## harness -- see issue 452 -- so what is asserted is which Control the engine
## picked and what `Control.get_tooltip` returns at that pixel.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""
var _failures := 0

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("HoverProbe: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	get_window().position = Vector2i(-4000, -4000)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	print("HoverProbe: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("HoverProbe: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	if not is_instance_valid(n) or n.is_queued_for_deletion():
		return []
	var out: Array[Node] = [n]
	for c in n.get_children(true):
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if is_instance_valid(n) and n is Button and n.is_visible_in_tree() \
				and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	print("HoverProbe: no visible button '%s'" % prefix)
	return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if is_instance_valid(n) and n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

## A real motion event at a real screen position, then the control the engine
## picked for it.
func _hover(at: Vector2) -> Control:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = Vector2(1.0, 1.0)
	get_viewport().push_input(e)
	await _settle(4)
	return get_viewport().gui_get_hovered_control()

## What the engine would put in the box, asked of the engine rather than of the
## resolver: `Control.get_tooltip` is what `Viewport` itself calls.
func _engine_tooltip(hovered: Control, at: Vector2) -> String:
	if hovered == null:
		return ""
	return hovered.get_tooltip(hovered.get_global_transform_with_canvas().affine_inverse() * at)

## One hover. `want` empty means the point must answer nothing at all -- the
## negative case, which is the one a hover layer covering the whole screen is
## most likely to get wrong.
func _check(what: String, at: Vector2, want: String, layer_only: bool = true) -> String:
	var hovered := await _hover(at)
	var said := _engine_tooltip(hovered, at)
	var picked: String = hovered.name if hovered != null else "<nothing>"
	var right_control := not layer_only or picked == HoverLayer.LAYER_NAME
	var ok := right_control and (said.contains(want) if want != "" else said == "")
	if not ok:
		_failures += 1
	print("HoverProbe: %-32s picked=%-14s says=%s" % [
		what, picked, said.replace("\n", " / ") if said != "" else "<nothing>"])
	if not ok:
		print("HoverProbe:   FAILED -- wanted %s" % [
			"silence" if want == "" else "a box containing '%s'" % want])
	return said

## The panel `_make_custom_tooltip` builds, put where the engine would put it.
## Placed by this probe, for the reason in the header.
func _photograph(hovered: Control, at: Vector2, said: String, name: String) -> void:
	if hovered == null or said == "":
		return
	var panel = hovered._make_custom_tooltip(said)
	if panel == null:
		return
	get_window().add_child(panel)
	await _settle(2)
	# Clamped into the window, which is what the engine does with its own popup.
	var room: Vector2 = get_viewport().get_visible_rect().size - panel.size
	panel.position = (at + Vector2(12.0, 12.0)).clamp(Vector2.ZERO, room.max(Vector2.ZERO))
	await _settle(3)
	await _shot(name)
	panel.queue_free()
	await _settle(2)

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var cards: Array[Node] = []
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			cards.append(n)
	for card in cards:
		if is_instance_valid(card) and card.class_def != null \
				and card.class_def.id in [&"geysermancer", &"warrior", &"priest"]:
			card.toggled.emit(true)
	await _settle()
	if not _press("start fight"):
		_failures += 1
		return
	await _settle()

	var battle = _node_with("BattleView.gd")
	if battle == null:
		print("HoverProbe: no battle screen")
		_failures += 1
		return

	## The other half of the hard requirement: the fight has not started, the
	## party is still draggable, and hovering an enemy must already work.
	if battle.setup:
		for u in battle.state.units:
			if u.team != CG.Team.ENEMY:
				continue
			var at := _screen(battle, BattleView.drawn_position(battle.state, u))
			var said := await _check("DURING PLACEMENT: %s" % u.display_name, at, "Enemy")
			await _photograph(await _hover(at), at, said, "teal_hover_during_placement")
			break
		if not _press("start fight"):
			_failures += 1
			return
		await _settle()
	else:
		print("HoverProbe: NOT EXERCISED -- the battle screen did not open in setup")
		_failures += 1

	## Far enough in that somebody is poisoned, out of resource and being shot
	## at, which is the state every complaint in the issue was made about.
	battle.set_process(false)
	var badge_unit: CombatUnit = null
	for tick in 900:
		battle._process(CG.TICK_SECONDS)
		badge_unit = _unit_with_badges(battle.state)
		if badge_unit != null and tick > 60:
			break
	await _settle()

	## The hard requirement: it works while the fight is held. Paused FIRST, so
	## nothing below can pass only because the simulation was feeding it.
	battle.set_paused(true)
	## Two of the issue's five complaints are about marks a fifteen-second fight
	## does not reliably produce: the "+N" chip needs three statuses at once and
	## the OOM tag needs a caster to run dry. Forced onto one pawn rather than
	## waited for -- this is a view probe, and a screenshot of a state nobody can
	## reproduce is worth less than one of a state that was arranged on purpose.
	badge_unit = _force_marks(battle.state)
	for id in battle._unit_views:
		battle._unit_views[id].sync(battle.state)
	battle._team_status.sync(battle.state)
	await _settle()

	var layer = _node_with("HoverLayer.gd")
	if layer == null:
		print("HoverProbe: the hover layer never attached itself")
		_failures += 1
		return
	print("HoverProbe: layer is a child of %s, filter=%d, fight paused=%s" % [
		layer.get_parent().name, layer.mouse_filter, battle.paused])

	await _check("empty sky", _screen(battle, _empty_point(battle.state)), "")

	for u in battle.state.units:
		if not u.alive:
			continue
		var at := _screen(battle, BattleView.drawn_position(battle.state, u))
		var said := await _check("%s body" % u.display_name, at,
			"Your party" if u.team == CG.Team.PLAYER else "Enemy")
		# The name is the box's heading rather than a line in its body, so it is
		# checked where it actually is.
		if not String(layer._title).contains(u.display_name):
			print("HoverProbe:   FAILED -- the box over %s is headed '%s'" % [u.display_name, layer._title])
			_failures += 1
		if u.team == CG.Team.ENEMY:
			await _photograph(await _hover(at), at, said, "teal_hover_enemy")
			break

	if badge_unit == null:
		print("HoverProbe: NOT EXERCISED -- no unit carried a mark under its body in 900 ticks")
		_failures += 1
	else:
		var shot := false
		for mark in UnitView.below_block_rects(badge_unit, battle.state.units):
			var want := ""
			match mark["kind"]:
				&"status":
					want = Glossary.status_text(mark["status"]).substr(0, 20)
				&"overflow":
					want = "badge row has no space"
				&"oom":
					want = "OOM means out of"
			var at := _screen(battle, (mark["rect"] as Rect2).get_center())
			var said := await _check("%s, %s mark" % [badge_unit.display_name, mark["kind"]], at, want)
			if not shot:
				await _photograph(await _hover(at), at, said, "teal_hover_badge")
				shot = true

	await _team_row(battle)

	## And the negative that matters most: a hover layer over the whole screen
	## must not eat the click the card opens on. #377's own complaint, put back
	## once already by a panel under the cursor.
	var target: CombatUnit = battle.state.units[0]
	await _click(_screen(battle, BattleView.drawn_position(battle.state, target)))
	var card_title: String = battle._unit_card._title.text if battle._unit_card.is_visible_in_tree() else ""
	print("HoverProbe: after a real click the card says '%s'" % card_title)
	if not card_title.begins_with(target.display_name):
		print("HoverProbe:   FAILED -- the hover layer ate the click")
		_failures += 1
	await _shot("teal_hover_click_still_works")

## The team panel's own rows, which are ordinary Controls and therefore hovered
## by the engine directly rather than through the layer.
func _team_row(battle) -> void:
	var panel = battle._team_status
	if panel == null:
		print("HoverProbe: NOT EXERCISED -- no team panel on this screen")
		_failures += 1
		return
	var shot := false
	for n in _walk(panel):
		if not (is_instance_valid(n) and n is Label and n.is_visible_in_tree() and n.tooltip_text != ""):
			continue
		var at: Vector2 = n.get_global_rect().get_center()
		var said := await _check("team row '%s'" % n.text, at, "hp" if not n.text.begins_with("+") else "badge row", false)
		if not shot and said != "":
			await _photograph(await _hover(at), at, said, "teal_hover_team_row")
			shot = true
	if not shot:
		print("HoverProbe: NOT EXERCISED -- no team row carried a hover box")
		_failures += 1

## The emptiest arena point there is, found rather than assumed: the seed moves
## every run, and a corner that was empty yesterday had a Goblin standing in it.
func _empty_point(state: CombatState) -> Vector2:
	var best := Vector2.ZERO
	var best_clearance := -1.0
	for ix in 17:
		for iy in 13:
			var at := Vector2(
				lerpf(-CG.ARENA_HALF_WIDTH * 0.95, CG.ARENA_HALF_WIDTH * 0.95, float(ix) / 16.0),
				lerpf(-CG.ARENA_HALF_HEIGHT * 0.95, CG.ARENA_HALF_HEIGHT * 0.95, float(iy) / 12.0))
			var clearance := INF
			for u in state.units:
				if u.alive:
					clearance = minf(clearance, BattleView.drawn_position(state, u).distance_to(at))
			if clearance > best_clearance:
				best_clearance = clearance
				best = at
	return best

func _force_marks(state: CombatState) -> CombatUnit:
	for u in state.units:
		if u.team != CG.Team.PLAYER or not u.alive or u.resource_max <= 0:
			continue
		u.resource = 0
		for s in [CG.Status.POISON, CG.Status.BLEED, CG.Status.SLOWED, CG.Status.MARKED]:
			u.statuses[s] = state.tick + CG.TICKS_PER_SECOND * 5
		u.status_magnitude[CG.Status.BLEED] = 3.0
		return u
	return null

func _unit_with_badges(state: CombatState) -> CombatUnit:
	var best: CombatUnit = null
	var most := 0
	for u in state.units:
		if not u.alive:
			continue
		var marks := UnitView.below_block_rects(u, state.units).size()
		if marks > most:
			most = marks
			best = u
	return best

func _screen(battle, arena_point: Vector2) -> Vector2:
	return battle._arena.get_global_transform() * arena_point

func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await _settle(3)
