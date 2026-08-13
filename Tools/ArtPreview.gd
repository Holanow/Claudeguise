extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const Silhouettes := preload("res://Scripts/Art/Silhouettes.gd")

## Draws every placeholder silhouette once, at the size it will actually appear
## in a fight, and saves a screenshot.
##
##   godot --path . Tools/ArtPreview.tscn
##
## MANAGER-OWNED. This is a look-at-it harness, not part of the game, which is
## why it lives in Tools/ and not in Scenes/ where it would collide with pike.
##
## It exists because "the art is fine" is not something to conclude from reading
## an array of coordinates. Every shape here was moved after seeing it rendered.

const CAPTURE_PATH := "res://Tools/preview/silhouettes.png"

const _COLUMNS := 4
const _CELL := Vector2(300.0, 200.0)
const _MARGIN := Vector2(60.0, 90.0)

## Drawn at two sizes: large enough to see what the shape is meant to be, and
## the size it will actually occupy on screen. A silhouette that reads well only
## at the large size has not solved the problem.
##
## The second number is derived rather than typed, and the first version of this
## file got it wrong by typing 12.0 — the world radius — which showed every
## shape smaller than it will ever appear and made them all look hopeless. The
## arena is CG.ARENA_HALF_WIDTH either side of the origin fitted across the
## viewport, so a world radius is multiplied by that scale before it reaches a
## pixel. Same class of error as measuring the right thing in the wrong units.
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
	&"grub": CG.DamageType.PROFANE,
	&"brute": CG.DamageType.EARTH,
}

const _ENEMY_SHAPES := [&"rat", &"grub", &"brute"]

func _ready() -> void:
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
