extends Node

## Issue 377: a blind playtester clicked directly on a sprite four times and
## got nothing back. This clicks the same way -- a real InputEventMouseButton
## at a real screen position, pushed into the viewport -- rather than calling
## the handler underneath.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("UnitClickProbe: refusing to run in the main checkout -- use a worktree.")
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
	print("UnitClickProbe: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	if not is_instance_valid(n) or n.is_queued_for_deletion():
		return []
	var out: Array[Node] = [n]
	for c in n.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if is_instance_valid(n) and n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	print("UnitClickProbe: no visible button '%s'" % prefix)
	return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if is_instance_valid(n) and n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await _settle(2)

## What the card is showing, or "" when nothing is. Read off the panel rather
## than off the view's own field, so a card that opened invisibly still reads
## as nothing.
func _card_text(battle) -> String:
	var card = battle.get("_unit_card")
	if card == null or not card.is_visible_in_tree():
		return ""
	return "%s | %s" % [card._title.text, card._body.text]

func _run() -> bool:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var cards: Array[Node] = []
	for n in _walk(_main):
		if is_instance_valid(n) and n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			cards.append(n)
	## Two pawns, and the Warrior deliberately not the first one: issue 397's
	## Plans button always opened party[0], which a one-pawn party cannot show.
	for want in [&"geysermancer", &"warrior"]:
		for card in cards:
			if is_instance_valid(card) and card.class_def != null and card.class_def.id == want:
				card.toggled.emit(true)
	await _settle()
	if not _press("start fight"):
		return false
	await _settle()
	if _node_with("DeployView.gd") != null:
		if not _press("start fight"):
			return false
		await _settle()

	var battle = _node_with("BattleView.gd")
	if battle == null:
		print("UnitClickProbe: no battle screen")
		return false

	## Far enough in that the Warrior has a target, statuses and a wind-up to
	## report, which is the state the playtester was looking at.
	battle.set_process(false)
	for tick in 90:
		battle._process(CG.TICK_SECONDS)
	await _settle()
	await _shot("wren_click_before")

	var failures := 0
	for u in battle.state.units:
		if not u.alive:
			continue
		## Where the sprite IS, not where the simulation keeps the unit: a melee
		## scrum nudges bodies apart by up to one and a half radii.
		var at: Vector2 = battle._arena.get_global_transform() * BattleView.drawn_position(battle.state, u)
		await _click(at)
		var text := _card_text(battle)
		var took := text.begins_with(u.display_name)
		print("UnitClickProbe: %-16s at %s  opened=%s  %s" % [u.display_name, at, took, text.replace("\n", " / ")])
		if not took:
			failures += 1
		if u.team == CG.Team.PLAYER:
			await _shot("wren_click_%s" % String(u.display_name).to_lower().replace(" ", "_"))

	## And the negative: empty sky is not a unit, and clicking it must put the
	## card away rather than leave the last one standing.
	await _click(battle._arena.get_global_transform() * Vector2(0.0, -CG.ARENA_HALF_HEIGHT * 0.92))
	var after := _card_text(battle)
	print("UnitClickProbe: after clicking empty space, card shows '%s'" % after)
	if after != "":
		failures += 1

	failures += await _plans_route(battle)

	print("UnitClickProbe: %d click(s) did nothing" % failures)
	return failures == 0

## Issue 397. Press Plans on each player pawn's own card and read back which
## pawn the plans screen landed on, and whether the card got out of its way.
func _plans_route(battle) -> int:
	var bad := 0
	print("UnitClickProbe: party order is %s" % str(battle.config.party.map(func(p): return p.display_name)))
	for u in battle.state.units:
		if not u.alive or u.pawn == null:
			continue
		await _click(battle._arena.get_global_transform() * BattleView.drawn_position(battle.state, u))
		if _card_text(battle) == "":
			continue
		battle._unit_card._plans_button.emit_signal("pressed")
		await _settle()
		var panel = battle._inspect_panel
		var landed: String = panel._pawns[panel._selected_index].display_name
		var covered: bool = battle._unit_card.is_visible_in_tree()
		print("UnitClickProbe: Plans on %-16s opened %-16s card still up=%s" % [u.display_name, landed, covered])
		if landed != u.display_name or covered:
			bad += 1
		await _shot("wren_plans_from_%s" % String(u.display_name).to_lower().replace(" ", "_"))
		panel.close()
		await _settle()
	return bad
