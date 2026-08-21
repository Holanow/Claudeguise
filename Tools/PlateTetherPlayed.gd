extends Node

## Issue 440's tether, reached the way a player reaches it: boot the real main
## scene, click four class cards and Start Fight, then shoot the fight once it
## is crowded. `Tools/PlateTetherShot.gd` renders `Battle.tscn` directly, which
## proves the pixels and not the path to them.

const OUT := "res://Screenshots/issue440_played_1280x720.png"
const LIVE := 9

var _main: Node
var _failures := 0
var _finished := false

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("PlateTetherPlayed: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	await _run()
	_check(_finished, "the probe ran to the end")
	print("PlateTetherPlayed: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _walk(n: Node) -> Array[Node]:
	if not is_instance_valid(n) or n.is_queued_for_deletion():
		return []
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _card_for(select: Node, cid: StringName) -> Control:
	for n in _walk(select):
		if n is Control and n.is_visible_in_tree() and n.get_script() != null \
			and n.get_script().resource_path.ends_with("PartyCard.gd") \
			and n.class_def != null and n.class_def.id == cid:
			return n
	return null

func _click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await _settle(2)

func _check(ok: bool, message: String) -> void:
	print("PlateTetherPlayed: %s %s" % ["ok  " if ok else "FAIL", message])
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
	_check(DisplayOptions.enabled(&"name_plates"), "name plates are on out of the box")

	# Re-found by class id before each click: clicking a card rebuilds the row,
	# so a list of nodes gathered once is stale by the second click.
	for cid in Registry.all_class_ids():
		var card := _card_for(select, cid)
		if card != null:
			await _click(card)
	_check(select.selected_pawns().size() >= 4,
		"%d pawns picked with real clicks" % select.selected_pawns().size())

	for step in 2:
		var start: Button = null
		for n in _walk(_main):
			if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with("start fight"):
				start = n
				break
		if start == null:
			_check(false, "no Start Fight button at step %d" % step)
			return
		await _click(start)

	var battle := _node_with("BattleView.gd")
	if battle == null:
		_check(false, "the fight never started")
		return

	var waited := 0
	while waited < 4000 and (battle.state == null or _live(battle.state) > LIVE):
		await get_tree().process_frame
		waited += 1
	_check(battle.state != null and _live(battle.state) <= LIVE,
		"the fight thinned to %d alive after %d frames" % [_live(battle.state), waited])

	var plates := 0
	for u in battle.state.units:
		if u.alive and UnitView.label_visible(u, battle.state):
			plates += 1
	_check(plates > 0, "%d name plates up, so there is something to tether" % plates)

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("PlateTetherPlayed: wrote %s at tick %d" % [OUT, battle.state.tick])
	_finished = true

static func _live(state) -> int:
	if state == null:
		return 99
	var n := 0
	for u in state.units:
		if u.alive:
			n += 1
	return n
