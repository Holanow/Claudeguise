extends RefCounted
class_name AppTheme

## One Theme, built from Palette so the values keep a single source. A hand
## written .tres would duplicate every colour and drift from Palette, which is
## the split issue 180 was filed for.

static var _shared: Theme = null

static func shared() -> Theme:
	if _shared != null:
		return _shared
	var t := Theme.new()
	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_font_size("font_size", "Label", Palette.FONT_SIZE_BODY)
	t.set_constant("separation", "HBoxContainer", int(Palette.SPACE_S))
	t.set_constant("separation", "VBoxContainer", int(Palette.SPACE_S))
	_shared = t
	return _shared

## Issue 396: the armor dropdown's six entries ran past the bottom of a 720px
## window with no scrollbar, so a player could not tell whether the list went
## on. A PopupMenu scrolls once its height is capped and overflows the screen
## until it is.
const POPUP_SCREEN_SHARE := 0.7

static func keep_popup_on_screen(picker: OptionButton) -> void:
	var popup := picker.get_popup()
	popup.about_to_popup.connect(func(): popup.max_size = Vector2i(0, popup_max_height(picker)))

## Measured at popup time, not at build time: the picker is usually built
## before it is in a tree, where there is no viewport to ask.
static func popup_max_height(control: Control) -> int:
	var height := 720.0
	if control.is_inside_tree():
		height = control.get_viewport_rect().size.y
	return int(height * POPUP_SCREEN_SHARE)
