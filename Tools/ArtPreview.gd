extends Node2D


## Draws every placeholder silhouette once, at the size it will actually appear
## in a fight, and saves a screenshot.

const CAPTURE_PATH := "res://Tools/preview/silhouettes.png"

const _COLUMNS := 4
const _CELL := Vector2(300.0, 200.0)
const _MARGIN := Vector2(60.0, 90.0)

## Drawn at two sizes: large enough to see what the shape is meant to be, and
## the size it will actually occupy on screen. A silhouette that reads well only
## at the large size has not solved the problem.
const _RADIUS_LARGE := 54.0
const _DEFAULT_UNIT_RADIUS := 12.0

func _screen_radius() -> float:
	var scale := get_viewport_rect().size.x / (CG.ARENA_HALF_WIDTH * 2.0)
	return _DEFAULT_UNIT_RADIUS * scale

## Accent colour per shape, so the preview shows the same pairing a fight will.
const _ACCENT := {
	&"warrior": CG.DamageType.EARTH,
	&"priest": CG.DamageType.DIVINE,
	&"geysermancer": CG.DamageType.WATER,
	&"siege_master": CG.DamageType.RAW,
	&"abomination": CG.DamageType.PROFANE,
	&"rat": CG.DamageType.PHYSICAL,
	&"rat_king": CG.DamageType.PHYSICAL,
	&"stalker": CG.DamageType.PHYSICAL,
	&"grub": CG.DamageType.PROFANE,
	&"brute": CG.DamageType.EARTH,
	&"goblin": CG.DamageType.PHYSICAL,
	&"goblin_archer": CG.DamageType.PHYSICAL,
	&"ghoul": CG.DamageType.PROFANE,
	&"cultist": CG.DamageType.PROFANE,
}

const _ENEMY_SHAPES := [
	&"rat_king", &"rat", &"grub", &"brute", &"stalker",
	&"goblin", &"goblin_archer", &"ghoul", &"cultist",
	&"dungeon_grunt", &"dungeon_archer", &"dungeon_cultist",
]

func _ready() -> void:
	if not Offscreen.require_renderer(self):
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture()
	get_tree().quit(0)

func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Tools/preview"))
	var err := image.save_png(CAPTURE_PATH)
	if err != OK:
		printerr("ArtPreview: could not save %s (error %d)" % [CAPTURE_PATH, err])
		return
	print("ArtPreview: wrote ", CAPTURE_PATH)

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var ids := Silhouettes.shape_ids()

	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Palette.BACKGROUND)
	draw_string(
		font, Vector2(_MARGIN.x, 44.0), "Placeholder silhouettes",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_HEADING, Palette.TEXT
	)
	draw_string(
		font, Vector2(_MARGIN.x, 66.0),
		"drawn as polygons in Scripts/Art/Silhouettes.gd  ·  left: readable size  ·  right: true on-screen size in the arena",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM
	)

	for i in ids.size():
		var id: StringName = ids[i]
		var cell := _MARGIN + Vector2(
			float(i % _COLUMNS) * _CELL.x,
			float(i / _COLUMNS) * _CELL.y
		)
		_draw_cell(font, id, cell)

func _draw_cell(font: Font, id: StringName, cell: Vector2) -> void:
	var team: CG.Team = CG.Team.ENEMY if _ENEMY_SHAPES.has(id) else CG.Team.PLAYER
	var accent: CG.DamageType = _ACCENT.get(id, CG.DamageType.PHYSICAL)

	# A patch of arena floor, so the shapes are judged against the ground they
	# will actually sit on rather than against a flat background.
	draw_rect(Rect2(cell, Vector2(_CELL.x - 24.0, _CELL.y - 34.0)), Palette.ARENA_FLOOR)

	var big_at := cell + Vector2(84.0, 96.0)
	draw_arc(big_at, _RADIUS_LARGE + 6.0, 0.0, TAU, 40, Palette.ARENA_EDGE, 1.0, true)
	_draw_at(big_at, id, _RADIUS_LARGE, team, accent)

	# Screen size, and a second copy facing the other way: these things spend a
	# fight walking at each other from both sides.
	var actual := _screen_radius()
	_draw_at(cell + Vector2(196.0, 96.0), id, actual, team, accent)
	_draw_at(cell + Vector2(196.0 + actual * 2.6, 96.0), id, actual, team, accent, true)

	draw_string(
		font, cell + Vector2(6.0, _CELL.y - 46.0), String(id),
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_BODY, Palette.TEXT
	)
	draw_string(
		font, cell + Vector2(6.0, _CELL.y - 30.0),
		"%s · %s" % [
			"enemy" if team == CG.Team.ENEMY else "player",
			CG.damage_type_name(accent),
		],
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM
	)

## Silhouettes draw around the origin with -Y up, so the draw is wrapped in a
## transform rather than every coordinate carrying an offset.
func _draw_at(at: Vector2, id: StringName, radius: float, team: CG.Team, accent: CG.DamageType, flip: bool = false) -> void:
	draw_set_transform(at, 0.0, Vector2.ONE)
	Silhouettes.draw_unit(self, id, radius, team, accent, flip)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
