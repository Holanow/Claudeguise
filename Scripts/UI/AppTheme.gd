extends RefCounted
class_name AppTheme

## One Theme, built from Palette so the values keep a single source. A hand
## written .tres would duplicate every colour and drift from Palette, which is
## the split issue 180 was filed for.

## Set `theme_type_variation` to this on a Label to give it the pre-printed
## voice: EB Garamond, letterspaced. Set the text in caps yourself.
const HEADING := &"LedgerHeading"
const COLUMN_HEAD := &"LedgerColumnHead"
const FIGURE := &"LedgerFigure"

static var _shared: Theme = null
static var _paper: Theme = null

## The dark theme. The arena's, and anything not yet converted.
static func shared() -> Theme:
	if _shared != null:
		return _shared
	var t := _common(Palette.TEXT, Palette.TEXT_DIM)
	_shared = t
	return _shared

## The ledger's. Issue 807: every information surface is a page the player
## reads, so a screen that is one sets this and every unstyled Label under it
## becomes ink on paper without a call site saying so.
static func paper() -> Theme:
	if _paper != null:
		return _paper
	var t := _common(Palette.INK, Palette.INK_DIM)
	t.set_color("font_color", "RichTextLabel", Palette.INK)
	t.set_color("default_color", "RichTextLabel", Palette.INK)
	t.set_stylebox("panel", "PanelContainer", UIArt.panel_style(&"", Palette.PAPER_FIELD, Palette.INK_DIM, 1, Palette.SPACE_S))
	t.set_stylebox("panel", "Panel", UIArt.panel_style(&"", Palette.PAPER_FIELD, Palette.INK_DIM, 1))

	# Buttons are the form's tabs: paper, a hairline rule, square corners.
	# Nothing here rounds a corner, because a printed rule does not have one.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(state, "Button", _tab(state))
		t.set_stylebox(state, "OptionButton", _tab(state))
	t.set_color("font_color", "Button", Palette.INK)
	t.set_color("font_hover_color", "Button", Palette.RULE_RED)
	t.set_color("font_pressed_color", "Button", Palette.RULE_RED)
	t.set_color("font_disabled_color", "Button", Palette.INK_FAINT)
	t.set_color("font_color", "OptionButton", Palette.INK)
	t.set_color("font_hover_color", "OptionButton", Palette.RULE_RED)
	t.set_font("font", "Button", FontLibrary.printed())
	t.set_font("font", "OptionButton", FontLibrary.entry())

	# A field you write in is a ruled blank, not a box. `Assets/UI/README.md`
	# already reserves the seed field from the panel art for this reason: its
	# edge is saying "type here" and a picture must not take that away.
	t.set_stylebox("normal", "LineEdit", _blank(Palette.INK_DIM))
	t.set_stylebox("focus", "LineEdit", _blank(Palette.RULE_RED))
	t.set_color("font_color", "LineEdit", Palette.INK)
	t.set_color("font_placeholder_color", "LineEdit", Palette.INK_FAINT)
	t.set_color("caret_color", "LineEdit", Palette.RULE_RED)

	t.set_stylebox("panel", "PopupMenu", UIArt.panel_style(&"", Palette.PAPER_FIELD, Palette.INK_DIM, 1, Palette.SPACE_XS))
	t.set_color("font_color", "PopupMenu", Palette.INK)
	t.set_color("font_hover_color", "PopupMenu", Palette.RULE_RED)
	t.set_font("font", "PopupMenu", FontLibrary.entry())

	# The doubled rule under a heading, as a control: two hairlines, three
	# apart. Every ruled account book has it and it is the cheapest thing on
	# this page that says which book we are in.
	t.set_stylebox("separator", "HSeparator", _double_rule())
	t.set_constant("separation", "HSeparator", 5)

	_variation(t, HEADING, "Label", FontLibrary.printed(), Palette.FONT_SIZE_HEADING, Palette.INK)
	_variation(t, COLUMN_HEAD, "Label", FontLibrary.printed(), Palette.FONT_SIZE_SMALL, Palette.RULE_RED)
	_variation(t, FIGURE, "Label", FontLibrary.entry_bold(), Palette.FONT_SIZE_BODY, Palette.INK)
	_paper = t
	return _paper

static func _common(text: Color, dim: Color) -> Theme:
	var t := Theme.new()
	t.set_font("font", "Label", FontLibrary.entry())
	t.set_font("font", "RichTextLabel", FontLibrary.entry())
	t.set_font("bold_font", "RichTextLabel", FontLibrary.entry_bold())
	t.set_font("font", "LineEdit", FontLibrary.entry())
	t.set_font("font", "CheckBox", FontLibrary.entry())
	t.set_color("font_color", "Label", text)
	t.set_font_size("font_size", "Label", Palette.FONT_SIZE_BODY)
	t.set_constant("separation", "HBoxContainer", int(Palette.SPACE_S))
	t.set_constant("separation", "VBoxContainer", int(Palette.SPACE_S))
	t.set_color("font_color", "CheckBox", text)
	t.set_color("font_hover_color", "CheckBox", dim)
	return t

static func _variation(t: Theme, name: StringName, base: StringName, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(name, base)
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)

static func _tab(state: String) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Palette.PAPER_FIELD if state != "pressed" else Palette.PAPER_SHADE
	if state == "hover":
		s.bg_color = Palette.PAPER_FIELD.lightened(0.25)
	s.border_color = Palette.RULE_RED if state == "focus" else Palette.INK_DIM
	s.set_border_width_all(1)
	s.set_content_margin_all(Palette.SPACE_S)
	s.content_margin_left = Palette.SPACE_M
	s.content_margin_right = Palette.SPACE_M
	return s

static func _blank(rule: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Palette.PAPER_FIELD
	s.bg_color.a = 0.35
	s.border_color = rule
	s.border_width_bottom = 2
	s.set_content_margin_all(Palette.SPACE_XS)
	s.content_margin_left = Palette.SPACE_S
	return s

static func _double_rule() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = Palette.INK_DIM
	s.border_width_top = 1
	s.border_width_bottom = 1
	return s

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
