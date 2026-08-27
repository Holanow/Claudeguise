extends Node

## Issue 496: the Burn Pit under a party nobody has configured, driven through
## the real menus, because the claim being checked is that a *default* game now
## shows pools.

const OUT_DIR := "res://Screenshots"
const TICKS := [40, 200]

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("SpoutPoolShot: refusing to run in the main checkout -- use a worktree.")
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
	print("SpoutPoolShot: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	print("SpoutPoolShot: no visible button '%s'" % prefix)
	return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _to_battle() -> Node:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var select := _node_with("PartySelect.gd")
	# Issue 538: the seed picks the ROSTER as well as the fight, and
	# assigning `.text` emits nothing, so the rolled pawns were random every
	# run. Submitted, and before the cards are read: a reroll frees them.
	select._seed_edit.text = "00000001"
	select._seed_edit.text_submitted.emit("00000001")
	await _settle()
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	for id in [&"geysermancer", &"warrior", &"priest", &"siege_master"]:
		if not by_id.has(id):
			print("SpoutPoolShot: no card for %s" % id)
			return null
		by_id[id].toggled.emit(true)
	await _settle()
	var picker: OptionButton = select._room_picker
	var picked := false
	for i in picker.item_count:
		if String(picker.get_item_metadata(i)).contains("hazard"):
			picker.selected = i
			picker.item_selected.emit(i)
			picked = true
	if not picked:
		print("SpoutPoolShot: the picker offers no burn pit")
		return null
	await _settle()
	if not _press("start fight"):
		return null
	await _settle()
	var held = _node_with("BattleView.gd")
	if held != null and held.setup:
		if not _press("start fight"):
			return null
		await _settle()
	var battle := _node_with("BattleView.gd")
	if battle == null:
		print("SpoutPoolShot: no battle screen")
		return null
	battle.set_process(false)
	return battle

func _run() -> bool:
	var battle := await _to_battle()
	if battle == null:
		return false
	var authored: int = battle.state.grid.count()
	var at := 0
	for want in TICKS:
		while at < want and battle.state.outcome == CombatState.Outcome.UNRESOLVED:
			battle._process(CG.TICK_SECONDS)
			at += 1
		await _settle(2)
		print("SpoutPoolShot: tick %d, terrain %d (room authored %d)" % [
			battle.state.tick, int(battle.state.grid.count()), authored])
		await _shot("swift_496_spout_pools_tick%d" % want)
	if int(battle.state.grid.count()) <= authored:
		print("SpoutPoolShot: the floor never changed -- nothing to show.")
		return false
	return true
