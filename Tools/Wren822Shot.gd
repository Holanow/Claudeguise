extends Node

## Issue 822: rooms scale to the party actually present. Picks a four-party and
## a ten-enemy room through the controls a player uses, and shows that both the
## summary and the fight itself hold the scaled count rather than the authored
## ten.

const OUT_DIR := "res://Screenshots"
const ROOM := &"floor1_room1"

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("Wren822Shot: use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	get_tree().quit(0)

func _settle(n: int = 8) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("Wren822Shot: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var select := _node_with("PartySelect.gd")

	var authored: int = RoomLibrary.get_room(ROOM).enemy_spawns.size()
	print("Wren822Shot: %s is authored with %d enemies" % [ROOM, authored])

	## The room first and the party second, which is the ordinary order and the
	## one that left the authored count on screen until the summary learned to
	## refresh on a party change.
	for i in select._room_picker.item_count:
		if select._room_picker.get_item_metadata(i) == ROOM:
			select._room_picker.selected = i
			select._room_picker.item_selected.emit(i)
	await _settle()
	print("Wren822Shot: with no party picked the summary reads '%s'" % select._room_summary.text)

	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	for id in [&"geysermancer", &"priest", &"siege_master", &"warrior"]:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()
	print("Wren822Shot: party of %d, summary reads '%s'" % [
		select.selected_pawns().size(), select._room_summary.text])
	await _shot("wren_822_party_reads_the_scaled_count")

	select._on_start_pressed()
	await _settle(30)
	var battle := _node_with("BattleView.gd")
	var enemies := 0
	for u in battle.state.units:
		if u.team == CG.Team.ENEMY:
			enemies += 1
	print("Wren822Shot: the fight that started holds %d enemies, authored %d" % [enemies, authored])
	await _shot("wren_822_fight_holds_the_scaled_count")
