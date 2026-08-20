extends Control
class_name DisplayOptionsPanel


## The one place display toggles are shown, built from `DisplayOptions.OPTIONS`.
##
## OWNER: wren.
##
## Data-driven rather than a hand-built row per option, so the next thing taken
## off the screen arrives with its checkbox and its explanation already wired.
##
## It sits on the battle screen because that is the screen being changed: the
## whole point of turning the numbers off is to change what you are looking at
## **while you are looking at it**, so a toggle behind a menu on another screen
## would be the wrong control however tidy.

signal changed()

var _rows: Array[CheckBox] = []

func _ready() -> void:
	theme = AppTheme.shared()
	visible = false
	# Sized to its contents and placed by the caller. Not a full-rect overlay:
	# it must be possible to watch the fight change as a box is ticked, which a
	# panel covering the arena would prevent.
	custom_minimum_size = Vector2(360.0, 0.0)

	var backdrop := PanelContainer.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_theme_stylebox_override("panel", _panel_style())
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(Palette.SPACE_M))
	margin.add_theme_constant_override("margin_top", int(Palette.SPACE_M))
	margin.add_theme_constant_override("margin_right", int(Palette.SPACE_M))
	margin.add_theme_constant_override("margin_bottom", int(Palette.SPACE_M))
	backdrop.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	var title := Label.new()
	title.text = "What to show"
	column.add_child(title)

	for option in DisplayOptions.OPTIONS:
		var box := CheckBox.new()
		box.text = option.label
		box.button_pressed = DisplayOptions.enabled(option.id)
		box.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
		var id: StringName = option.id
		box.toggled.connect(func(pressed: bool):
			DisplayOptions.set_enabled(id, pressed)
			changed.emit())
		column.add_child(box)
		_rows.append(box)

		var help := Label.new()
		help.text = option.help
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
		help.add_theme_color_override("font_color", Palette.TEXT_DIM)
		column.add_child(help)

## Re-read the values before showing. The state is static and survives a screen
## being rebuilt, so a freshly-built panel would otherwise show the defaults
## while the game is running on the player's choices.
func refresh() -> void:
	for i in mini(_rows.size(), DisplayOptions.OPTIONS.size()):
		_rows[i].set_pressed_no_signal(DisplayOptions.enabled(DisplayOptions.OPTIONS[i].id))

func toggle_visible() -> void:
	if not visible:
		refresh()
	visible = not visible

## Issue 268. Through `UIArt.panel_style`, so `Assets/UI/panel.png` re-skins
## this panel the way the README has always claimed it does. With no file
## present it is the identical `StyleBoxFlat` this built by hand.
##
## The rounded corner belongs to the fallback and not to the pipeline: a
## nine-sliced PNG paints its own corners, and `StyleBoxTexture` has no corner
## radius to set. Same rule as `PartyCard`'s selection ring -- what the
## generated default draws is not automatically what a dropped-in picture must.
func _panel_style() -> StyleBox:
	var style := UIArt.panel_style(&"", Palette.BACKGROUND, Palette.ARENA_EDGE, 2)
	if style is StyleBoxFlat:
		style.set_corner_radius_all(4)
	return style
