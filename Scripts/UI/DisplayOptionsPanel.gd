extends Control
class_name DisplayOptionsPanel


## The one place display toggles are shown, built from `DisplayOptions.OPTIONS`.

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
		box.button_pressed = DisplayOptions.enabled(option.id)
		box.text = row_text(option.label, box.button_pressed)
		box.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
		## The engine's tick is dark art on this game's dark panel and no colour
		## can lift it, so the row is given the look every other control on the
		## battle screen has (issue 323).
		for state in ["normal", "hover", "pressed", "focus"]:
			box.add_theme_stylebox_override(state, _row_style(state == "hover"))
		var id: StringName = option.id
		var label: String = option.label
		box.toggled.connect(func(pressed: bool):
			box.text = row_text(label, pressed)
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
		var option = DisplayOptions.OPTIONS[i]
		var on := DisplayOptions.enabled(option.id)
		_rows[i].set_pressed_no_signal(on)
		_rows[i].text = row_text(option.label, on)

## The state of the option in words. The tick beside it was the whole report of
## this control and it was measured at 2 points of luminance over the panel.
static func row_text(label: String, on: bool) -> String:
	return "%s: %s" % [label, "showing" if on else "hidden"]

## A row that looks like the buttons the player has already pressed to get here.
func _row_style(hover: bool) -> StyleBox:
	var bg := Palette.BACKGROUND.lightened(0.12 if hover else 0.06)
	var style := UIArt.panel_style(&"", bg, Palette.ARENA_EDGE, 1)
	if style is StyleBoxFlat:
		style.set_corner_radius_all(4)
		style.content_margin_left = Palette.SPACE_S
		style.content_margin_right = Palette.SPACE_S
	return style

func toggle_visible() -> void:
	if not visible:
		refresh()
	visible = not visible

## Issue 268. Through `UIArt.panel_style`, so `Assets/UI/panel.png` re-skins
## this panel the way the README has always claimed it does. With no file
## present it is the identical `StyleBoxFlat` this built by hand.
func _panel_style() -> StyleBox:
	var style := UIArt.panel_style(&"", Palette.BACKGROUND, Palette.ARENA_EDGE, 2)
	if style is StyleBoxFlat:
		style.set_corner_radius_all(4)
	return style
