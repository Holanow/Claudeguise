extends Node

## Issue 824: the Siege Master's "Build the engine" row on the screen the player
## reads it on, scrolled into frame, so the gate it states can be compared
## against `build_siege_engine`'s 40 Mana without opening the source.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _failures := 0

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	print("BuildRowShot: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _settle(n: int = 8) -> void:
	for i in n:
		await get_tree().process_frame
		await get_tree().process_frame

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

## Every widget carrying text, whatever class the panel used to draw it.
func _texts(root: Node) -> Array:
	var out := []
	for c in _walk(root):
		if c is Label or c is Button:
			out.append(c)
	return out

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var select: Node = null
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartySelect.gd"):
			select = n
	if select == null:
		printerr("BuildRowShot: no party screen")
		_failures += 1
		return
	var panel = select._inspect_panel
	var pawn = null
	for p in select.available_pawns():
		if p.pawn_class != null and p.pawn_class.id == &"siege_master":
			pawn = p
	if pawn == null:
		printerr("BuildRowShot: no Siege Master on the party screen")
		_failures += 1
		return
	## Clicked, not `show_pawn`: the equipment doll rebinds off the card press,
	## so calling the panel directly leaves another class's body under the rows.
	if not select._cards.has(pawn.id):
		printerr("BuildRowShot: no Siege Master card")
		_failures += 1
		return
	var card: Control = select._cards[pawn.id]
	var at := card.get_global_rect().get_center()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await _settle(2)
	await _settle()

	var wanted: Control = null
	for c in _texts(panel):
		var t: String = c.text
		if t.to_lower().contains("resource at least"):
			print("BuildRowShot: '%s'" % t)
			if wanted == null:
				wanted = c
	if wanted == null:
		printerr("BuildRowShot: the library shows no resource gate for the Siege Master")
		_failures += 1
		return

	var scroller: Node = wanted
	while scroller != null and not (scroller is ScrollContainer):
		scroller = scroller.get_parent()
	if scroller is ScrollContainer:
		var s := scroller as ScrollContainer
		s.scroll_vertical = int(wanted.global_position.y - s.global_position.y + s.scroll_vertical - 140)
		await _settle()

	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_viewport().get_texture().get_image().save_png("%s/finch_824_build_row.png" % OUT_DIR)
	print("BuildRowShot: finch_824_build_row.png")
