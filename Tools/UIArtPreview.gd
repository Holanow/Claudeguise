extends Node2D


## Every status badge and every ability icon, drawn at readable size and at the
## size they will actually be, plus the nine-slice border path. Same reasoning
## as Tools/ArtPreview.gd and Tools/AttackFXPreview.gd: "the shapes are fine" is
## not a conclusion to reach from reading a coordinate table.

const CAPTURE_PATH := "res://Screenshots/ui_icons_sheet.png"

const _MARGIN := 50.0

var _font: Font = null

## Held in a member, not a local. Built as a local inside `_draw()` it rendered
## as three solid white boxes: the ImageTexture is RefCounted, `_draw()` returns
## before the render server draws the queued command, the last reference goes
## with the stack frame, the RID is freed, and Godot falls back to white. The
## shipped path is not exposed to this -- `UIArt._cache` holds every dropped-in
## texture for the life of the process -- but anyone building a texture on the
## fly to draw once will hit it.
var _border_tex: Texture2D = null

func _ready() -> void:
	if not Offscreen.require_renderer(self):
		return
	# Printed, not assumed. The project uses a canvas_items stretch with a design
	# width, so `--resolution 1500x1340` does NOT give a 1500-wide drawing space:
	print("UIArtPreview: logical viewport is ", get_viewport_rect().size)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture()
	get_tree().quit(0)

func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	var err := image.save_png(CAPTURE_PATH)
	if err != OK:
		printerr("UIArtPreview: could not save %s (error %d)" % [CAPTURE_PATH, err])
		return
	print("UIArtPreview: wrote ", CAPTURE_PATH)

func _statuses(harmful: bool) -> Array:
	var out: Array = []
	for s in CG.Status.values():
		if CG.is_harmful(s) == harmful:
			out.append(s)
	return out

func _label(at: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw() -> void:
	_font = ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Palette.BACKGROUND)

	_label(Vector2(_MARGIN, 40.0), "Status badges and ability icons", Palette.FONT_SIZE_HEADING, Palette.TEXT)
	_label(Vector2(_MARGIN, 66.0),
		"PLAYTEST-NOTES-2 items 2 and 3. Generated defaults -- a PNG dropped into Assets/UI replaces any of them.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	var y := 110.0
	y = _draw_statuses(y)
	y = _draw_actions(y + 30.0)
	_draw_bars_and_borders(y + 30.0)

## The rule made visible: the two groups side by side, so an upward cool wedge
## and a downward hot wedge can be compared at the size they will be seen at.
func _draw_statuses(top: float) -> float:
	_label(Vector2(_MARGIN, top), "Statuses -- beneficial points up, harmful points down. Both rows at 44px, then 16px, then 12px.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	var y := top + 24.0
	for harmful in [false, true]:
		var list := _statuses(harmful)
		var row := Vector2(_MARGIN, y)
		# A patch of real arena floor under each row: these are read against the
		# arena, not against the page background, and the difference matters at
		# 12px.
		draw_rect(Rect2(row - Vector2(10.0, 6.0), Vector2(float(list.size()) * 118.0 + 20.0, 106.0)), Palette.ARENA_FLOOR)
		for i in list.size():
			var s = list[i]
			var x := row.x + float(i) * 118.0
			StatusIcons.draw_status(self, s, Rect2(x, row.y, 44.0, 44.0))
			StatusIcons.draw_status(self, s, Rect2(x + 52.0, row.y + 8.0, 16.0, 16.0))
			StatusIcons.draw_status(self, s, Rect2(x + 52.0, row.y + 28.0, 12.0, 12.0))
			_label(Vector2(x - 4.0, row.y + 66.0), String(CG.Status.keys()[s]).capitalize(),
				Palette.FONT_SIZE_SMALL, StatusIcons.rim_color(s))
		_label(Vector2(row.x + float(list.size()) * 118.0 + 30.0, row.y + 26.0),
			"harmful" if harmful else "beneficial", Palette.FONT_SIZE_BODY,
			StatusIcons.rim_color(list[0]))
		y += 120.0
	return y

func _draw_actions(top: float) -> float:
	_label(Vector2(_MARGIN, top), "Abilities -- one icon per action in the registry. 40px, then 16px (the size at the end of a wind-up bar). Colour is the action's own damage type.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	var ids := ActionLibrary.all_ids()
	# 6 columns at 200 fits the 1280-wide logical viewport measured in _ready.
	var cols := 6
	var col_w := 200.0
	var row_h := 92.0
	var y := top + 26.0
	for i in ids.size():
		var id: StringName = ids[i]
		var action = ActionLibrary.get_action(id)
		var dt: CG.DamageType = action.damage_type if action != null else CG.DamageType.RAW
		var x := _MARGIN + float(i % cols) * col_w
		var cy := y + floorf(float(i) / float(cols)) * row_h
		draw_rect(Rect2(x - 6.0, cy - 6.0, 176.0, 76.0), Palette.ARENA_FLOOR)
		ActionIcons.draw_action(self, id, dt, Rect2(x, cy, 40.0, 40.0))
		ActionIcons.draw_action(self, id, dt, Rect2(x + 48.0, cy + 12.0, 16.0, 16.0))
		_label(Vector2(x - 2.0, cy + 62.0), String(id), Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	return y + ceilf(float(ids.size()) / float(cols)) * row_h

## Two things the note asks for that only exist once something is drawn: the
## progress bar with the icon at its end (item 3), and the border drop-in
## (item 15). The bar here is a mock -- the real one is wren's -- but the icon
## at the end of it is the shipped call.
func _draw_bars_and_borders(top: float) -> void:
	_label(Vector2(_MARGIN, top), "Item 3, at true size: a wind-up progress bar with the icon at its end. Four charge levels of the Warrior's Execute, then the Geysermancer's Blast.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	var y := top + 26.0
	var samples := [[&"warrior_execute", 0.15], [&"warrior_execute", 0.5], [&"warrior_execute", 0.9], [&"geyser_blast", 0.6], [&"priest_heal", 0.35]]
	for i in samples.size():
		var id: StringName = samples[i][0]
		var progress: float = samples[i][1]
		var action = ActionLibrary.get_action(id)
		var dt: CG.DamageType = action.damage_type if action != null else CG.DamageType.RAW
		var x := _MARGIN + float(i) * 240.0
		draw_rect(Rect2(x - 8.0, y - 8.0, 220.0, 48.0), Palette.ARENA_FLOOR)
		_bar(Vector2(x, y + 4.0), 56.0, progress, dt)
		ActionIcons.draw_action(self, id, dt, Rect2(x + 62.0, y - 2.0, 20.0, 20.0))
		_label(Vector2(x, y + 34.0), "%s %d%%" % [id, int(progress * 100.0)], Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	var by := y + 70.0
	_label(Vector2(_MARGIN, by), "Item 15, the border path: left is the generated fallback (no file), right is the same call with a nine-slice PNG present. Corners stay corners at any panel size.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	by += 26.0
	UIArt.draw_border(self, Rect2(_MARGIN, by, 220.0, 90.0), Palette.ARENA_EDGE, 1.0)
	_label(Vector2(_MARGIN + 16.0, by + 50.0), "draw_border, no PNG", Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	if _border_tex == null:
		_border_tex = _demo_border_texture()
	var tex := _border_tex
	# Saved alongside the sheet so a nine-slice that looks wrong can be told
	# apart from a source PNG that is wrong. That is what settled the white
	# boxes: the source PNG came out correct, which ruled the art out and left
	# the draw, and the draw turned out to be a lifetime bug rather than
	# geometry.
	tex.get_image().save_png("res://Screenshots/ui_border_source.png")
	UIArt.draw_nine_slice(self, tex, Rect2(_MARGIN + 260.0, by, 220.0, 90.0))
	UIArt.draw_nine_slice(self, tex, Rect2(_MARGIN + 510.0, by, 90.0, 90.0))
	UIArt.draw_nine_slice(self, tex, Rect2(_MARGIN + 630.0, by, 400.0, 44.0))
	_label(Vector2(_MARGIN + 276.0, by + 50.0), "draw_nine_slice, three sizes, one 24px PNG", Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

func _bar(at: Vector2, width: float, progress: float, dt: CG.DamageType) -> void:
	var h := 6.0
	draw_rect(Rect2(at, Vector2(width, h)), Palette.HP_BACK)
	draw_rect(Rect2(at, Vector2(width * progress, h)), Palette.damage_color(dt))

## A deliberately obvious 24x24 frame, built in memory rather than committed as
## a file: this proves the nine-slice maths, and shipping a real border PNG
## would replace the generated defaults everywhere, which is the player's
## decision and not mine.
func _demo_border_texture() -> Texture2D:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 24:
		for y in 24:
			var edge := x < 2 or y < 2 or x > 21 or y > 21
			var corner := (x < 8 and y < 8) or (x < 8 and y > 15) or (x > 15 and y < 8) or (x > 15 and y > 15)
			if edge:
				img.set_pixel(x, y, Palette.TEAM_PLAYER if corner else Palette.ARENA_EDGE)
			elif corner and (x < 5 or y < 5 or x > 18 or y > 18):
				img.set_pixel(x, y, Palette.TEAM_PLAYER)
	return ImageTexture.create_from_image(img)
