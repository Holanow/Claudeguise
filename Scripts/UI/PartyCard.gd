extends Control
class_name PartyCard


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

## How far inside a dropped-in border the selection ring is drawn. Enough to
## clear a decorated frame's own corner detail, which `UIArt.draw_nine_slice`
## sizes at a third of the PNG's shorter side.
const SELECTION_INSET := 4.0

## Hover-info-box system, phase 1: the whole card is one tooltip, reading
## the same three tags it already draws (role/style/method) rather than a
## separate mechanism per tag — there is no sub-region hit-testing on a
## custom-drawn Control without building phase 2's arena-style hit-test
## early for no reason, and a class's three tags are read together as a
## trio everywhere else in the game (this card's own text, InspectPanel's
## header line), not one at a time.
var class_def: ClassDef = null:
	set(value):
		class_def = value
		tooltip_text = Glossary.class_tags_text(value.role_primary, value.style, value.method) if value != null else ""
		queue_redraw()
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL

## Issue 112: left-click still picks the pawn, right-click pins the card's
## glossary popout. The card's own class name is the popout's title, since the
## card draws its text rather than carrying a Label to read it off.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		toggled.emit(not selected)
		accept_event()
		return
	var title := class_def.display_name if class_def != null else ""
	if PopoutHost.handle_input(self, event, title, tooltip_text):
		accept_event()

func _make_custom_tooltip(for_text: String) -> Object:
	return GlossaryTooltip.build(for_text)

func _draw() -> void:
	if class_def == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Palette.ARENA_FLOOR)
	_draw_frame(rect)

	_draw_silhouette(Vector2(size.x * 0.5, SILHOUETTE_CENTER_Y))

	var font := ThemeDB.fallback_font
	_centered_text(font, class_def.display_name, 128.0, Palette.FONT_SIZE_BODY, Palette.TEXT)
	_centered_text(font, _role_text(), 154.0, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	_centered_text(font, _style_text(), 174.0, Palette.FONT_SIZE_SMALL, Palette.damage_color(_accent()))

## The card's frame, through the drop-in pipeline: with
## `Assets/UI/panel_border.png` present this is that PNG, nine-sliced; with no
## file it is the flat outline this function used to draw inline. PLAYTEST-
## NOTES-2 item 15 asked for a way to drop in artier interface elements, and
## `UIArt.draw_border` was written for it and had no game caller at all --
## found by sable in #103 and flagged rather than deleted, correctly.
##
## **Without a file this draws exactly the pixels it drew before**: same colour,
## same rect, same thickness, passed straight through as `draw_border`'s
## fallback. That is deliberate. This is a path for the player's art, not new
## art from us.
##
## Selection is the one thing a dropped-in border must not be able to erase. A
## nine-slice is drawn as painted, colour included, so it cannot carry the
## selected/unselected distinction the fallback carries in `border_color`. When
## art is present the selection ring is drawn inside it instead, in the same
## Palette token, so the card still says which four you picked whatever the
## border looks like. `UIArt.has_art` is what asks, and this is its first
## caller too.
func _draw_frame(rect: Rect2) -> void:
	var border_color := Palette.TEAM_PLAYER if selected else Palette.ARENA_EDGE
	var thickness := 3.0 if selected else 1.0
	UIArt.draw_border(self, rect, border_color, thickness)
	if selected and UIArt.has_art(&"panel_border"):
		draw_rect(rect.grow(-SELECTION_INSET), Palette.TEAM_PLAYER, false, thickness)

## sable, 2026-08-19: this called `Silhouettes.build_parts` and drew the polygons
## by hand, so **every party card showed the placeholder outline while all five
## classes had real sprites in `Assets/Units/`.** `build_parts` warned about
## exactly that in its own doc comment. `draw_unit` takes a `center` for this
## case, which is what the comment here used to say it did not.
func _draw_silhouette(center: Vector2) -> void:
	Silhouettes.draw_unit(self, class_def.id, SILHOUETTE_RADIUS, CG.Team.PLAYER,
		_accent(), false, center)

func _accent() -> int:
	if not class_def.damage_types.is_empty():
		return class_def.damage_types[0]
	return CG.DamageType.PHYSICAL

## Issue 19: "ANTI_SUPPORT" is a raw enum name with an underscore on the
## first screen of the game — the same developer-language problem as the
## win screen's tick count, found on this card the moment someone looked.
## String's own capitalize() turns SCREAMING_SNAKE into Title Case.
func _role_text() -> String:
	return String(CG.Role.keys()[class_def.role_primary]).capitalize()

func _style_text() -> String:
	return "%s · %s" % [
		String(CG.Style.keys()[class_def.style]).capitalize(),
		String(CG.Method.keys()[class_def.method]).capitalize(),
	]

func _centered_text(font: Font, text: String, y: float, font_size: int, color: Color) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
