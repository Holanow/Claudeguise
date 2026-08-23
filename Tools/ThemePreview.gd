extends Control


## The theming half of `UIArt` (issue #115), rendered with art and without it,
## side by side, in the node types the real screens are actually built from.

const CAPTURE_BARE := "res://Screenshots/ui_theming_no_file.png"
const CAPTURE_THEMED := "res://Screenshots/ui_theming_dropped_in.png"

## TWO PASSES IN ONE PROCESS, AND THE FIRST VERSION OF THIS TOOL WAS WRONG.
func _ready() -> void:
	if not Offscreen.require_renderer(self):
		return
	print("ThemePreview: logical viewport is ", get_viewport_rect().size)
	_remove_demo_art()
	UIArt.clear_cache()
	_build()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(CAPTURE_BARE)

	_write_demo_art()
	UIArt.clear_cache()
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_build()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(CAPTURE_THEMED)

	_remove_demo_art()
	get_tree().quit(0)

## Deliberately obvious frames and a deliberately obvious background, built in
## memory rather than committed. Shipping real theme PNGs would replace the
## generated defaults everywhere, and which art this game ships with is the
## player's decision -- the whole reason the pipeline exists is that their file
## lands without a session in the middle interpreting it.
func _write_demo_art() -> void:
	DirAccess.make_dir_recursive_absolute("res://Assets/UI/panel")
	DirAccess.make_dir_recursive_absolute("res://Assets/UI/background")
	_frame_png("res://Assets/UI/panel.png", Palette.TEAM_PLAYER)
	_frame_png("res://Assets/UI/panel/inspect.png", Palette.RESOURCE_RAGE)
	_frame_png("res://Assets/UI/panel_border.png", Palette.TEAM_PLAYER)
	_background_png("res://Assets/UI/background.png")

func _remove_demo_art() -> void:
	DirAccess.remove_absolute("res://Assets/UI/panel.png")
	DirAccess.remove_absolute("res://Assets/UI/panel_border.png")
	DirAccess.remove_absolute("res://Assets/UI/panel/inspect.png")
	DirAccess.remove_absolute("res://Assets/UI/background.png")
	DirAccess.remove_absolute("res://Assets/UI/panel")
	DirAccess.remove_absolute("res://Assets/UI/background")

func _frame_png(path: String, accent: Color) -> void:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Palette.ARENA_FLOOR)
	for x in 24:
		for y in 24:
			var edge := x < 2 or y < 2 or x > 21 or y > 21
			var corner := (x < 8 or x > 15) and (y < 8 or y > 15)
			if edge:
				img.set_pixel(x, y, accent if corner else Palette.ARENA_EDGE)
			elif corner and (x < 5 or y < 5 or x > 18 or y > 18):
				img.set_pixel(x, y, accent)
	img.save_png(path)

## Wider than it is tall, on purpose: a background PNG whose aspect does not
## match the screen is the normal case, and the point of `STRETCH_KEEP_ASPECT_
## COVERED` is that it crops rather than leaving bars.
func _background_png(path: String) -> void:
	var img := Image.create(64, 24, false, Image.FORMAT_RGBA8)
	for x in 64:
		for y in 24:
			var band := (x + y) / 6 % 2 == 0
			img.set_pixel(x, y, Palette.BACKGROUND.lightened(0.16 if band else 0.04))
	img.save_png(path)

func _capture(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	if image.save_png(path) != OK:
		printerr("ThemePreview: could not save ", path)
		return
	print("ThemePreview: wrote ", path)

func _build() -> void:
	# Left asks for an element with no file of its own, so it shows what the
	# GENERAL file does -- one panel.png re-skinning everything.
	_column(Vector2(40.0, 90.0), &"no_file_of_its_own", "general file only")
	# Right asks for `inspect`, which has a file of its own, so it shows the
	# SPECIFIC override winning without disturbing anything else.
	_column(Vector2(660.0, 90.0), &"inspect", "specific override for this element")

	var title := Label.new()
	title.text = "UI theming (#115): the same calls with and without a dropped-in file"
	title.position = Vector2(40.0, 28.0)
	title.add_theme_font_size_override("font_size", Palette.FONT_SIZE_HEADING)
	title.add_theme_color_override("font_color", Palette.TEXT)
	add_child(title)

	var note := Label.new()
	note.text = "The right column also shows the rule: a picture may replace decoration, it may not replace information."
	note.position = Vector2(40.0, 62.0)
	note.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	note.add_theme_color_override("font_color", Palette.TEXT_DIM)
	add_child(note)

func _column(at: Vector2, element: StringName, heading: String) -> void:
	var box := Control.new()
	box.position = at
	box.size = Vector2(560.0, 620.0)
	add_child(box)

	var bg := UIArt.background_node(element, Palette.BACKGROUND)
	box.add_child(bg)

	var head := Label.new()
	head.text = heading
	head.position = Vector2(8.0, 4.0)
	head.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	head.add_theme_color_override("font_color", Palette.TEXT)
	box.add_child(head)

	_panel(box, Rect2(8.0, 40.0, 260.0, 90.0), element, "panel_style, small")
	_panel(box, Rect2(8.0, 144.0, 540.0, 90.0), element, "panel_style, wide -- corners stay corners")
	_panel(box, Rect2(288.0, 40.0, 260.0, 90.0), &"a_second_element", "a second element, general file")

	# The state-signal demonstration, and the reason this tool renders both
	# columns rather than one. A selected card has to stay visibly selected after
	# a border PNG is dropped in, and the only way to know is to drop one in.
	_selectable(box, Rect2(8.0, 250.0, 260.0, 110.0), element, true, "SELECTED")
	_selectable(box, Rect2(288.0, 250.0, 260.0, 110.0), element, false, "not selected")

func _panel(parent: Control, rect: Rect2, element: StringName, text: String) -> void:
	var panel := PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel",
		UIArt.panel_style(element, Palette.ARENA_FLOOR, Palette.ARENA_EDGE, 1, Palette.SPACE_S))
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	panel.add_child(label)
	parent.add_child(panel)

## `PartyCard`'s pattern, reproduced so the rule can be seen rather than
## described: draw the themed frame, then draw the selection ring INSIDE it when
## art is present, because a nine-slice is painted and cannot carry state.
func _selectable(parent: Control, rect: Rect2, element: StringName, selected: bool, text: String) -> void:
	var card := _SelectableCard.new()
	card.position = rect.position
	card.size = rect.size
	card.element = element
	card.selected = selected
	parent.add_child(card)
	var label := Label.new()
	label.text = "%s\n(selection stays visible either way)" % text
	label.position = Vector2(12.0, 12.0)
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", Palette.TEXT if selected else Palette.TEXT_DIM)
	card.add_child(label)

class _SelectableCard extends Control:
	const _Palette := preload("res://Scripts/Core/Palette.gd")
	const _UIArt := preload("res://Scripts/Art/UIArt.gd")

	var element: StringName = &""
	var selected: bool = false

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		_UIArt.draw_background(self, rect, element, _Palette.HP_BACK)
		var accent := _Palette.TEAM_PLAYER if selected else _Palette.ARENA_EDGE
		_UIArt.draw_border(self, rect, accent, 2.0, element)
		# The whole point. With no art the border colour carried "selected". With
		# art the border is painted and cannot, so the ring is drawn inside it.
		if selected and _UIArt.border_art_name(element) != &"":
			draw_rect(rect.grow(-5.0), _Palette.TEAM_PLAYER, false, 2.0)
