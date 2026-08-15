extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const StatusIcons := preload("res://Scripts/Art/StatusIcons.gd")
const ActionIcons := preload("res://Scripts/Art/ActionIcons.gd")
const GlossaryTooltip := preload("res://Scripts/UI/GlossaryTooltip.gd")
const PopoutHost := preload("res://Scripts/UI/PopoutHost.gd")

## One small icon with a word beside it, hoverable and pinnable.
##
## OWNER: wren.
##
## Issue 113 asks for "mostly icons and bars **as long as definitions are
## clear**", and the second half is the binding one. Everything the arena draws
## today is drawn inside a `_draw()` on `UnitView`, which means no part of it can
## be hovered, and a status badge on a pawn is a shape a player either already
## knows or never learns. A `Control` can be hovered and, through `PopoutHost`,
## right-clicked to pin -- so the team panel's icons are the first icons in this
## game that answer a question about themselves.
##
## Two kinds, because the panel needs exactly two and a third would be
## speculation: a status plate (`StatusIcons`) and an action plate
## (`ActionIcons`). Both are the vocabulary already on screen, per the issue's
## "it should reuse, not reinvent".
##
## `mouse_filter` is set to STOP in `_ready`. It is `Control`'s default, but the
## eighth built-and-unreachable feature on this project was a `Label` whose
## default was IGNORE, so on this project it gets written down rather than
## assumed.

enum Kind { STATUS, ACTION }

const ICON_SIZE := 18.0
const TEXT_GAP := 3.0

var kind: Kind = Kind.STATUS
var status: CG.Status = CG.Status.SHIELD
var action_id: StringName = &""
var damage_type: CG.DamageType = CG.DamageType.PHYSICAL

## Word beside the icon. Empty draws the icon alone at ICON_SIZE square.
var text: String = ""
var text_color: Color = Palette.TEXT_DIM

## 0.0 to 1.0 of the icon darkened from the top down, the share of a cooldown
## still to run. Negative means "no sweep", which is every status chip and an
## action chip that is ready.
##
## Down from the top rather than up from the bottom because the shrinking dark
## band is the thing a player is waiting on, and a band that shrinks toward the
## floor reads as draining while one that grows up from it reads as filling.
var sweep: float = -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(measured_width(), ICON_SIZE)

func measured_width() -> float:
	if text == "":
		return ICON_SIZE
	var font := ThemeDB.fallback_font
	return ICON_SIZE + TEXT_GAP + font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL).x

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(ICON_SIZE, ICON_SIZE))
	if kind == Kind.STATUS:
		StatusIcons.draw_status(self, status, rect)
	else:
		ActionIcons.draw_action(self, action_id, damage_type, rect)
	if sweep > 0.0:
		# Over the icon, not instead of it: the player still has to be able to
		# tell which action is waiting, which is the whole reason a cooldown
		# indicator names an action rather than lighting a lamp.
		var shade := Palette.BACKGROUND
		shade.a = 0.66
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * minf(sweep, 1.0))), shade)
	if text != "":
		var font := ThemeDB.fallback_font
		var baseline := ICON_SIZE * 0.5 + float(Palette.FONT_SIZE_SMALL) * 0.35
		draw_string(font, Vector2(ICON_SIZE + TEXT_GAP, baseline), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, text_color)

## Issue 245: the hover box gets the same title the pinned copy gets, so the two
## surfaces name the thing once each rather than the body carrying a name the
## popout then repeats above it.
func _make_custom_tooltip(for_text: String) -> Object:
	return GlossaryTooltip.build(for_text, pin_title)

## Issue 112's gesture, unchanged. The title is what the chip says where it says
## anything and the icon's own name otherwise, because a pinned popout with no
## title cannot be told from the one pinned beside it.
var pin_title: String = ""

func _gui_input(event: InputEvent) -> void:
	if PopoutHost.handle_input(self, event, pin_title if pin_title != "" else text, tooltip_text):
		accept_event()
