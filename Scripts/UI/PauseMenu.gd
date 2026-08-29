extends PanelContainer
class_name PauseMenu


## Issue 825: the battle screen is all game, so the five toolbar buttons become
## one card that Escape opens and Escape closes.

## Ledger stock laid on the record, not a page the record is mounted in: the
## arena is full-bleed underneath and this is the only parchment left on screen.
const CARD_WIDTH := 320.0

signal resume_pressed
signal plans_pressed
signal restart_pressed
signal settings_pressed
signal change_party_pressed

var _caption: VBoxContainer = null

static func create() -> PauseMenu:
	var menu := PauseMenu.new()
	menu._build()
	return menu

func _build() -> void:
	name = "PauseMenu"
	theme = AppTheme.paper()
	add_theme_stylebox_override("panel", UIArt.panel_style(
		&"card", Palette.PAPER_FIELD, Palette.BINDING, 2, Palette.SPACE_M))
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(CARD_WIDTH, 0.0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(Palette.SPACE_S))
	add_child(column)

	var heading := Label.new()
	heading.text = "Paused"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	AppTheme.as_heading(heading)
	column.add_child(heading)

	## The party, the room and the seed used to be a header row over the arena.
	## They are reference, not live, and "Restart (same seed)" is unreadable
	## without the seed beside it.
	_caption = VBoxContainer.new()
	_caption.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	column.add_child(_caption)

	column.add_child(_rule())

	_add_button(column, "Resume", func(): resume_pressed.emit())
	_add_button(column, "Plans & Equipment", func(): plans_pressed.emit())
	_add_button(column, "Restart (same seed)", func(): restart_pressed.emit())
	_add_button(column, "Settings", func(): settings_pressed.emit())

	column.add_child(_rule())

	_add_button(column, "Change party", func(): change_party_pressed.emit())

	var hint := Label.new()
	hint.text = "Escape closes this."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Palette.INK_FAINT)
	hint.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	column.add_child(hint)

## The caption labels are owned by `BattleView`, which writes their text when a
## fight begins; this only gives them a home.
func adopt_caption(labels: Array) -> void:
	for label in labels:
		if label != null and label.get_parent() == null:
			_caption.add_child(label)

func _add_button(column: VBoxContainer, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
	button.pressed.connect(on_press)
	column.add_child(button)
	return button

func _rule() -> Control:
	var rule := ColorRect.new()
	rule.color = Palette.RULE_FEINT
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

## Which of this card's buttons exist, by label, so a test can read the menu
## without walking the tree of a live scene.
func button_labels() -> Array[String]:
	var out: Array[String] = []
	for node in get_child(0).get_children():
		if node is Button:
			out.append(node.text)
	return out
