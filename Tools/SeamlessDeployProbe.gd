extends Node

## Placement on the battle screen, driven the way a player drives it: real
## `InputEventMouseButton` and `InputEventMouseMotion` pushed into the viewport,
## so Godot's own picking decides what was hit.

## `emit_signal("pressed")` bypasses hit-testing and has passed over two real
## defects this week, so even the buttons are clicked at their screen position.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("SeamlessDeployProbe: refusing to run in the main checkout -- use a worktree.")
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
	print("SeamlessDeployProbe: %s_%s.png" % [name, _tag])

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
		if is_instance_valid(n) and n is Button and n.is_visible_in_tree() \
				and n.text.to_lower().begins_with(prefix.to_lower()):
			return n
	return null

func _button_event(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.pressed = pressed
	e.position = at
	e.global_position = at
	return e

func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		get_viewport().push_input(_button_event(at, pressed))
		await _settle(2)

func _click_button(prefix: String) -> bool:
	var b := _button(prefix)
	if b == null:
		print("SeamlessDeployProbe: no visible button '%s'" % prefix)
		return false
	await _click(b.get_global_rect().get_center())
	return true

## Press, several motions, release -- the events a hand produces. Coalesced
## motion is why the release carries the final position too.
func _drag(from: Vector2, to: Vector2, steps: int = 6) -> void:
	get_viewport().push_input(_button_event(from, true))
	await _settle(2)
	var previous := from
	for i in range(1, steps + 1):
		var at := from.lerp(to, float(i) / float(steps))
		var m := InputEventMouseMotion.new()
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.position = at
		m.global_position = at
		m.relative = at - previous
		previous = at
		get_viewport().push_input(m)
		await _settle(1)
	get_viewport().push_input(_button_event(to, false))
	await _settle(2)

func _card_text(battle) -> String:
	var card = battle.get("_unit_card")
	if card == null or not card.is_visible_in_tree():
		return ""
	return card._title.text

func _screen_point(battle, world: Vector2) -> Vector2:
	return battle._arena.get_global_transform() * world

func _pawn_ids(battle) -> Array[int]:
	var out: Array[int] = []
	for u in battle.state.units:
		if u.team == CG.Team.PLAYER and u.enemy_id == &"":
			out.append(u.id)
	return out

func _run() -> bool:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var cards: Array[Node] = []
	for n in _walk(_main):
		if is_instance_valid(n) and n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			cards.append(n)
	for want in [&"warrior", &"priest", &"geysermancer"]:
		for card in cards:
			if is_instance_valid(card) and card.class_def != null and card.class_def.id == want:
				card.toggled.emit(true)
	await _settle()

	if not await _click_button("start fight"):
		return false
	await _settle()

	var battle = _node_with("BattleView.gd")
	if battle == null:
		print("SeamlessDeployProbe: Start Fight did not reach the battle screen")
		return false

	var failures := 0

	## 1. The battle screen is where placement happens now. No second screen, no
	## ticks spent, the band up and the party draggable.
	print("SeamlessDeployProbe: screen after Start Fight is '%s'" % _main._current.name)
	print("SeamlessDeployProbe: setup=%s paused=%s tick=%d band=%s button='%s'" % [
		battle.setup, battle.paused, battle.state.tick,
		battle._deploy_band != null and battle._deploy_band.visible,
		battle._pause_button.text])
	if _main._current.name != "Battle" or not battle.setup or battle.state.tick != 0:
		failures += 1
	await _shot("wren_seamless_1_placing")

	## 2. A real drag on a real pawn. The pawn has to end up under the pointer
	## and nothing may open.
	var ids := _pawn_ids(battle)
	if ids.is_empty():
		print("SeamlessDeployProbe: no pawns to drag")
		return false
	var first: int = ids[0]
	var before: Vector2 = battle.state.unit(first).position
	var to_world := Vector2(-260.0, 150.0)
	await _drag(_screen_point(battle, BattleView.drawn_position(battle.state, battle.state.unit(first))),
		_screen_point(battle, to_world))
	var after: Vector2 = battle.state.unit(first).position
	print("SeamlessDeployProbe: DRAG %s -> %s (wanted %s), card='%s'" % [before, after, to_world, _card_text(battle)])
	if after.distance_to(to_world) > 1.0:
		failures += 1
	if _card_text(battle) != "":
		print("SeamlessDeployProbe: a drag also opened the card")
		failures += 1
	await _shot("wren_seamless_2_dragged")

	## 3. A real click on the same pawn, same button, no motion. This one must
	## open the card and must not move anybody: it is the whole disambiguation.
	var held: Vector2 = battle.state.unit(first).position
	await _click(_screen_point(battle, BattleView.drawn_position(battle.state, battle.state.unit(first))))
	var opened := _card_text(battle)
	print("SeamlessDeployProbe: CLICK opened '%s', pawn now at %s" % [opened, battle.state.unit(first).position])
	if opened == "":
		failures += 1
	if battle.state.unit(first).position.distance_to(held) > 1.0:
		print("SeamlessDeployProbe: a click moved the pawn")
		failures += 1
	await _shot("wren_seamless_3_clicked")
	battle._unit_card.close()
	await _settle()

	## 4. The enemy side is not draggable, and a pawn cannot be pushed past the
	## band. Both are refusals, so both need measuring rather than assuming.
	var enemy = null
	for u in battle.state.units:
		if u.team == CG.Team.ENEMY:
			enemy = u
			break
	if enemy != null:
		var enemy_before: Vector2 = enemy.position
		await _drag(_screen_point(battle, BattleView.drawn_position(battle.state, enemy)),
			_screen_point(battle, Vector2(-400.0, 0.0)))
		print("SeamlessDeployProbe: dragging an enemy moved it %s" % str(enemy.position - enemy_before))
		if enemy.position != enemy_before:
			failures += 1
		battle._unit_card.close()
		await _settle()

	await _drag(_screen_point(battle, BattleView.drawn_position(battle.state, battle.state.unit(first))),
		_screen_point(battle, Vector2(CG.ARENA_HALF_WIDTH - 10.0, 0.0)))
	var pushed: Vector2 = battle.state.unit(first).position
	print("SeamlessDeployProbe: dragged past the line, landed at x=%.1f (line %.1f)" % [pushed.x, CG.party_deploy_max_x()])
	if pushed.x > CG.party_deploy_max_x() + 0.001:
		failures += 1

	## 5. Unpause it. The same button, and the fight has to actually run.
	var placement: Array[Vector2] = battle.placements()
	if not await _click_button("start fight"):
		return false
	await _settle()
	var running = _node_with("BattleView.gd")
	print("SeamlessDeployProbe: after Start Fight setup=%s paused=%s band=%s button='%s'" % [
		running.setup, running.paused,
		running._deploy_band != null and running._deploy_band.visible,
		running._pause_button.text])
	if running.setup or running.paused:
		failures += 1

	## 6. The party starts the fight where it was left, and the first tick moves
	## it from there rather than from wherever the room authored.
	var at_start: Array[Vector2] = []
	for id in _pawn_ids(running):
		at_start.append(running.state.unit(id).position)
	print("SeamlessDeployProbe: placed %s\nSeamlessDeployProbe: fight  %s" % [placement, at_start])
	for i in placement.size():
		if at_start[i].distance_to(placement[i]) > 0.001:
			print("SeamlessDeployProbe: pawn %d started at %s, not %s" % [i, at_start[i], placement[i]])
			failures += 1

	running.set_process(false)
	running._process(CG.TICK_SECONDS)
	await _settle()
	print("SeamlessDeployProbe: after one tick, tick=%d" % running.state.tick)
	if running.state.tick != 1:
		failures += 1
	await _shot("wren_seamless_4_first_tick")

	print("SeamlessDeployProbe: %d failure(s)" % failures)
	return failures == 0
