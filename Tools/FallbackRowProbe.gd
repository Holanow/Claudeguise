extends Node

## Issue 414: how tall the fallback row actually is in the party screen's
## column, measured off the laid-out control rather than counted by eye.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""

func _ready() -> void:
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	get_tree().quit(0)

func _settle(n: int = 8) -> void:
	for i in n:
		await get_tree().process_frame

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _labels(n: Node) -> Array:
	var out := []
	for c in _walk(n):
		if c is Label:
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
		print("FallbackRowProbe: no party screen")
		return
	var panel = select._inspect_panel
	var pawn = panel._pawns[0]
	print("FallbackRowProbe: %s, %d plans" % [pawn.display_name, pawn.plans.size()])
	await _settle()

	var rows: Array = []
	for n in _walk(panel):
		if n is Control and n.name.begins_with(InspectPanel.FALLBACK_ROW_NAME):
			rows.append(n)
	print("FallbackRowProbe: %d fallback row(s)" % rows.size())
	for row in rows:
		var lines := 0
		var texts: Array[String] = []
		for label in _labels(row):
			lines += label.get_line_count()
			texts.append("%s [%d line(s), %.0fpx wide]" % [label.text, label.get_line_count(), label.size.x])
		print("FallbackRowProbe: row %.0fpx tall, %d wrapped line(s) over %d chip(s)"
			% [row.size.y, lines, texts.size()])
		for t in texts:
			print("    " + t)

	## The row sits under the library, so the shot has to scroll to it the way
	## a player would.
	if not rows.is_empty():
		var scroller: Node = rows[0]
		while scroller != null and not (scroller is ScrollContainer):
			scroller = scroller.get_parent()
		if scroller is ScrollContainer:
			(scroller as ScrollContainer).scroll_vertical = int(rows[0].global_position.y
				- (scroller as ScrollContainer).global_position.y
				+ (scroller as ScrollContainer).scroll_vertical - 120)
			await _settle()

	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_viewport().get_texture().get_image().save_png("%s/issue414_fallback_%s.png" % [OUT_DIR, _tag])
	print("FallbackRowProbe: wrote issue414_fallback_%s.png" % _tag)
