extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const Silhouettes := preload("res://Scripts/Art/Silhouettes.gd")

## One selectable class: silhouette, name, role and style, coloured by its
## damage type. The whole card is the touch target — Palette.TOUCH_TARGET_MIN
## exists because a checkbox glyph in front of a word is nowhere near it.
##
## OWNER: pike.
##
## Issue 17: this is what a player chooses between, and choosing was
## previously a checkbox next to a bare class name. `ClassDef` already
## carries everything a card needs; nothing here is new game data.

signal toggled(pressed: bool)

const CARD_SIZE := Vector2(170.0, 200.0)
const SILHOUETTE_RADIUS := 42.0
const SILHOUETTE_CENTER_Y := 70.0

var class_def: ClassDef = null
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		toggled.emit(not selected)
		accept_event()

func _draw() -> void:
	if class_def == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Palette.ARENA_FLOOR)
	var border_color := Palette.TEAM_PLAYER if selected else Palette.ARENA_EDGE
	draw_rect(rect, border_color, false, 3.0 if selected else 1.0)

	_draw_silhouette(Vector2(size.x * 0.5, SILHOUETTE_CENTER_Y))

	var font := ThemeDB.fallback_font
	_centered_text(font, class_def.display_name, 128.0, Palette.FONT_SIZE_BODY, Palette.TEXT)
	_centered_text(font, _role_text(), 154.0, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	_centered_text(font, _style_text(), 174.0, Palette.FONT_SIZE_SMALL, Palette.damage_color(_accent()))

## Reuses Silhouettes.build_parts rather than draw_unit, which assumes it is
## drawing centred on the canvas's own origin: a card needs the silhouette
## offset to sit above its text, not at the card's top-left corner.
func _draw_silhouette(center: Vector2) -> void:
	for part in Silhouettes.build_parts(class_def.id, SILHOUETTE_RADIUS, CG.Team.PLAYER, _accent(), false):
		var points: PackedVector2Array = part["points"]
		var offset_points := PackedVector2Array()
		for p in points:
			offset_points.append(p + center)
		if part["filled"]:
			draw_colored_polygon(offset_points, part["fill"])
		var closed := offset_points.duplicate()
		closed.append(offset_points[0])
		draw_polyline(closed, part["outline"], part["outline_width"], true)

func _accent() -> int:
	if not class_def.damage_types.is_empty():
		return class_def.damage_types[0]
	return CG.DamageType.PHYSICAL

func _role_text() -> String:
	return CG.Role.keys()[class_def.role_primary]

func _style_text() -> String:
	return "%s · %s" % [CG.Style.keys()[class_def.style], CG.Method.keys()[class_def.method]]

func _centered_text(font: Font, text: String, y: float, font_size: int, color: Color) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
