extends Node

## Issue 351: the three-column party screen. Pawns left, the selected pawn's
## plans and equipment in the middle, where to fight and Start on the right.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("PartyScreenShot: use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	get_tree().quit(0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("PartyScreenShot: %s_%s.png" % [name, _tag])

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
	await _shot("wren_party_three_columns_fresh")

	var select := _node_with("PartySelect.gd")
	var cards: Array[Node] = []
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			cards.append(n)
	for i in mini(4, cards.size()):
		cards[i].toggled.emit(true)
	await _settle()
	await _shot("wren_party_three_columns_picked")

	## The pawn the middle column is about, chosen the way a player chooses it.
	if cards.size() > 1:
		cards[1].toggled.emit(true)
	await _settle()
	print("PartyScreenShot: middle column is showing %s" % select.focused_pawn().display_name)
	await _shot("wren_party_three_columns_focused")
