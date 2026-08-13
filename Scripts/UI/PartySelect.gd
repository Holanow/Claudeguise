extends Control

const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const PartyCardScript := preload("res://Scripts/UI/PartyCard.gd")

## Pick up to four pawns and a seed, then start the fight.
##
## OWNER: pike.
##
## Swapping the party between runs is an acceptance criterion for this slice, so
## this screen is not a placeholder. It generates one pawn per class from
## Registry.all_class_ids() and lets the player choose.
##
## Issue 17: the only decision in this slice happens here, and a checkbox next
## to a bare class name did not let anyone make it. Each class is now a card
## (PartyCard) showing its silhouette, role and style, and the whole card is
## the touch target.

signal battle_requested(config: RunConfig)

const MAX_PARTY_SIZE := 4

var _available: Array[PawnData] = []
var _selected: Array[PawnData] = []
var _cards: Dictionary = {}

var _status_label: Label = null
var _start_button: Button = null
var _seed_edit: LineEdit = null
var _roster_box = null

func _ready() -> void:
	_build_roster()
	_build_ui()
	_update_status()

func _build_roster() -> void:
	_available.clear()
	for class_id in Registry.all_class_ids():
		var cls: ClassDef = Registry.get_class_def(class_id)
		if cls == null:
			continue
		var pawn := PawnData.new()
		pawn.id = class_id
		pawn.display_name = cls.display_name
		pawn.pawn_class = cls
		_available.append(pawn)

## `window/stretch/mode` is `canvas_items` with aspect `expand` (project-wide,
## the phone-legibility pass): the whole UI is authored in one fixed logical
## coordinate space and Godot scales the render uniformly to fit any real
## window or device, the same way BattleView's arena already does. A wrap
## container computing columns from `get_viewport_rect()` therefore does not
## get narrower on a physical phone — that call reports design-space size,
## not physical pixels, by design (`expand` never reports *less* than the
## design width). A fixed, compact grid plus the project's existing uniform
## scaling is the right fit for how this project already handles size,
## rather than a second, competing responsive scheme.
const CARD_COLUMNS := 3

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BACKGROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_top", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_right", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_bottom", int(Palette.SPACE_L))
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(Palette.SPACE_M))
	margin.add_child(column)

	var title := Label.new()
	title.text = "Pick your party"
	title.add_theme_font_size_override("font_size", Palette.FONT_SIZE_HEADING)
	title.add_theme_color_override("font_color", Palette.TEXT)
	column.add_child(title)

	_roster_box = GridContainer.new()
	_roster_box.columns = CARD_COLUMNS
	_roster_box.add_theme_constant_override("h_separation", int(Palette.SPACE_M))
	_roster_box.add_theme_constant_override("v_separation", int(Palette.SPACE_M))
	column.add_child(_roster_box)

	if _available.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No classes available yet."
		empty_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_roster_box.add_child(empty_label)
	else:
		for pawn in _available:
			var card := Control.new()
			card.set_script(PartyCardScript)
			# Called directly rather than left to the engine: this node may
			# be built while PartySelect itself is not yet in a live tree
			# (a test calling _ready() directly, same pattern the rest of
			# Scripts/UI/ uses), and custom_minimum_size has to be set
			# either way for the touch-target guarantee to hold.
			card._ready()
			card.class_def = pawn.pawn_class
			card.toggled.connect(_on_card_toggled.bind(pawn))
			_roster_box.add_child(card)
			_cards[pawn.id] = card

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", int(Palette.SPACE_S))
	column.add_child(seed_row)

	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	seed_label.add_theme_color_override("font_color", Palette.TEXT)
	seed_row.add_child(seed_label)

	_seed_edit = LineEdit.new()
	_seed_edit.text = "%08X" % (randi() & 0xFFFFFFFF)
	_seed_edit.custom_minimum_size = Vector2(220.0, Palette.TOUCH_TARGET_MIN)
	_seed_edit.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	_seed_edit.add_theme_color_override("font_color", Palette.TEXT)
	_seed_edit.add_theme_stylebox_override("normal", _seed_box_style())
	_seed_edit.add_theme_stylebox_override("focus", _seed_box_style())
	seed_row.add_child(_seed_edit)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	_status_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(_status_label)

	_start_button = Button.new()
	_start_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	_start_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	_start_button.pressed.connect(_on_start_pressed)
	column.add_child(_start_button)

## A bordered box, not a bare underline, so it reads as an editable field
## rather than a label — issue 17's "the seed control should look like
## something you can edit".
func _seed_box_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.ARENA_FLOOR
	style.border_color = Palette.ARENA_EDGE
	style.set_border_width_all(2)
	style.set_content_margin_all(Palette.SPACE_S)
	return style

func _on_card_toggled(pressed: bool, pawn: PawnData) -> void:
	if pressed and _selected.size() >= MAX_PARTY_SIZE and not _selected.has(pawn):
		_flash_party_full()
		return
	toggle_pawn(pawn, pressed)

## Trying to add a fifth pawn used to do nothing visible at all. A message
## that stands out (colour, not just a number changing) rather than the
## selection silently refusing to grow.
func _flash_party_full() -> void:
	if _status_label != null:
		_status_label.text = "Party full — remove one first"
		_status_label.add_theme_color_override("font_color", Palette.HP_LOW)

## Public so tests can drive selection without touching the card tree.
func toggle_pawn(pawn: PawnData, selected: bool) -> void:
	if selected:
		if not _selected.has(pawn) and _selected.size() < MAX_PARTY_SIZE:
			_selected.append(pawn)
	else:
		_selected.erase(pawn)
	if _cards.has(pawn.id):
		_cards[pawn.id].selected = _selected.has(pawn)
	_update_status()

func selected_pawns() -> Array[PawnData]:
	return _selected.duplicate()

func available_pawns() -> Array[PawnData]:
	return _available.duplicate()

## Seed round-trips through Main: called with the last run's seed when the
## player comes back from a fight, so "run the same fight again" survives a
## trip through party select rather than rerolling on every visit.
func prefill_seed(seed_text: String) -> void:
	if _seed_edit != null:
		_seed_edit.text = seed_text

func _update_status() -> void:
	if _status_label != null:
		_status_label.text = "Party: %d/%d" % [_selected.size(), MAX_PARTY_SIZE]
		_status_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	if _start_button != null:
		_start_button.disabled = _selected.is_empty()
		_start_button.text = "Pick at least one class" if _selected.is_empty() else "Start Fight"

func _on_start_pressed() -> void:
	battle_requested.emit(current_config())

func current_config() -> RunConfig:
	var config := RunConfig.new()
	config.party = _selected.duplicate()
	var encounters := Registry.all_encounter_ids()
	config.encounter_id = encounters[0] if not encounters.is_empty() else &""
	config.seed = RunConfig.parse_seed(_seed_edit.text) if _seed_edit != null else 0
	return config
