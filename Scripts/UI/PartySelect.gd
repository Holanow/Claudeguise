extends Control

const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")

## Pick up to four pawns and a seed, then start the fight.
##
## OWNER: pike.
##
## Swapping the party between runs is an acceptance criterion for this slice, so
## this screen is not a placeholder. It generates one pawn per class from
## Registry.all_class_ids() and lets the player choose.

signal battle_requested(config: RunConfig)

const MAX_PARTY_SIZE := 4

var _available: Array[PawnData] = []
var _selected: Array[PawnData] = []
var _checkboxes: Dictionary = {}

var _status_label: Label = null
var _start_button: Button = null
var _seed_edit: LineEdit = null

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

	var roster_box := VBoxContainer.new()
	roster_box.add_theme_constant_override("separation", int(Palette.SPACE_S))
	column.add_child(roster_box)

	if _available.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No classes available yet."
		empty_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
		roster_box.add_child(empty_label)
	else:
		for pawn in _available:
			var row := CheckBox.new()
			row.text = pawn.display_name
			row.add_theme_color_override("font_color", Palette.TEXT)
			row.toggled.connect(_on_toggled.bind(pawn, row))
			roster_box.add_child(row)
			_checkboxes[pawn.id] = row

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", int(Palette.SPACE_S))
	column.add_child(seed_row)

	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.add_theme_color_override("font_color", Palette.TEXT)
	seed_row.add_child(seed_label)

	_seed_edit = LineEdit.new()
	_seed_edit.text = "%08X" % (randi() & 0xFFFFFFFF)
	_seed_edit.custom_minimum_size = Vector2(160.0, 0.0)
	seed_row.add_child(_seed_edit)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(_status_label)

	_start_button = Button.new()
	_start_button.text = "Start Fight"
	_start_button.pressed.connect(_on_start_pressed)
	column.add_child(_start_button)

func _on_toggled(pressed: bool, pawn: PawnData, box: CheckBox) -> void:
	if pressed:
		if _selected.size() >= MAX_PARTY_SIZE:
			box.set_pressed_no_signal(false)
			return
		toggle_pawn(pawn, true)
	else:
		toggle_pawn(pawn, false)

## Public so tests can drive selection without touching the checkbox tree.
func toggle_pawn(pawn: PawnData, selected: bool) -> void:
	if selected:
		if not _selected.has(pawn) and _selected.size() < MAX_PARTY_SIZE:
			_selected.append(pawn)
	else:
		_selected.erase(pawn)
	_update_status()

func selected_pawns() -> Array[PawnData]:
	return _selected.duplicate()

func available_pawns() -> Array[PawnData]:
	return _available.duplicate()

func _update_status() -> void:
	if _status_label != null:
		_status_label.text = "Party: %d/%d" % [_selected.size(), MAX_PARTY_SIZE]
	if _start_button != null:
		_start_button.disabled = _selected.is_empty()

func _on_start_pressed() -> void:
	battle_requested.emit(current_config())

func current_config() -> RunConfig:
	var config := RunConfig.new()
	config.party = _selected.duplicate()
	var encounters := Registry.all_encounter_ids()
	config.encounter_id = encounters[0] if not encounters.is_empty() else &""
	config.seed = RunConfig.parse_seed(_seed_edit.text) if _seed_edit != null else 0
	return config
