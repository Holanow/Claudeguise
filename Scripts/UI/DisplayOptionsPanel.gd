extends Control
class_name DisplayOptionsPanel


## The one place display toggles are shown, built from `DisplayOptions.OPTIONS`.

signal changed()

const PANEL_WIDTH := 420.0

var _rows: Array[CheckBox] = []
var _scroll: ScrollContainer = null
var _column: VBoxContainer = null

## Every state a row can be drawn in. `hover_pressed` is the one a screenshot
## caught missing: a ticked row under the pointer fell back to the engine's
## empty box and lost its outline.
const ROW_STATES := ["normal", "hover", "pressed", "hover_pressed", "focus"]

func _ready() -> void:
	theme = AppTheme.shared()
	visible = false
	# Sized to its contents and placed by the caller. Not a full-rect overlay:
	# it must be possible to watch the fight change as a box is ticked, which a
	# panel covering the arena would prevent.
	## Issue 396: 360 was narrow enough that "Poison and burn ticks in the log:
	## hidden" ran into the panel's own right edge.
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)

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

	## The list scrolls, because the list grows: two options fitted 720px and
	## four do not, and a fourth option nobody can reach is the defect this
	## panel exists to have fixed (issue 319).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(_scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(column)
	_column = column

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
		for state in ROW_STATES:
			box.add_theme_stylebox_override(state, _row_style(state.contains("hover")))
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
		fit_to_screen()
	visible = not visible

## As tall as its contents, or as tall as the room under it, whichever is less.
## Measured rather than capped at a constant: 520 would fit 1280x720 and run off
## the bottom of a 844x390 launch, which this panel has done before.
func fit_to_screen() -> void:
	if _scroll == null or not is_inside_tree():
		return
	fit_within(get_viewport_rect().size.y - position.y - Palette.SPACE_M)

## Issue 396: `room` is room for the whole panel, and the scroll is not the
## whole panel. The margin around it and the two-pixel border were not
## subtracted, so the panel overshot the bottom of the screen by its own chrome
## and lost its border and its last line.
const CHROME_HEIGHT := 2.0 * Palette.SPACE_M + 4.0

## Split from the measurement so the arithmetic can be tested without a window.
func fit_within(room: float) -> void:
	if _scroll == null:
		return
	var wanted := _column.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = maxf(Palette.TOUCH_TARGET_MIN, minf(wanted, room - CHROME_HEIGHT))

## Issue 268. Through `UIArt.panel_style`, so `Assets/UI/panel.png` re-skins
## this panel the way the README has always claimed it does. With no file
## present it is the identical `StyleBoxFlat` this built by hand.
func _panel_style() -> StyleBox:
	var style := UIArt.panel_style(&"", Palette.BACKGROUND, Palette.ARENA_EDGE, 2)
	if style is StyleBoxFlat:
		style.set_corner_radius_all(4)
	return style
