extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const PartyCardScript := preload("res://Scripts/UI/PartyCard.gd")
const InspectPanelScript := preload("res://Scripts/UI/InspectPanel.gd")

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
signal run_requested(config: RunConfig)
signal level_editor_requested

const MAX_PARTY_SIZE := 4

var _available: Array[PawnData] = []
var _selected: Array[PawnData] = []
var _cards: Dictionary = {}

var _status_label: Label = null
var _start_button: Button = null
var _start_run_button: Button = null
var _seed_edit: LineEdit = null
var _roster_box = null
var _inspect_panel = null

func _ready() -> void:
	_build_roster()
	_build_ui()
	_update_status()

## Issue 21b found this the moment the inspect screen tried to show a pawn's
## plans and had none to show: this roster built PawnData by hand and never
## set `plans`, so every real playthrough (party select is the only place a
## fightable pawn is ever built) has run on DefaultBehavior alone — no preset
## plan has fired outside a test or a devtools script. PawnFactory is the one
## place that already does this correctly; using it here instead of
## hand-building fixes the roster and the fight itself, not just the screen.
func _build_roster() -> void:
	_available.clear()
	for class_id in Registry.all_class_ids():
		var cls: ClassDef = Registry.get_class_def(class_id)
		if cls == null:
			continue
		_available.append(PawnFactory.make_starter_pawn(class_id, class_id, cls.display_name))

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
##
## Issue 18: rook's own eyeballed read of party_select_phone_400x800.png was
## "every card well under the 48-pixel touch minimum". Measured instead with
## get_global_rect() (Control's coordinates are always logical, the same as
## custom_minimum_size — the stretch scale is applied at render/input-mapping
## time, not by resizing controls): every card is 170x200, over three times
## TOUCH_TARGET_MIN on its short side, at any window size. Godot maps a real
## tap back through the same stretch transform, so this is the actual
## functional target, not merely a number that happens not to shrink. The
## real complaint underneath — cards crammed into the top of the screen with
## most of the height empty — is legitimate on its own and worth fixing
## regardless: two columns instead of three spreads the five classes over
## three rows rather than two, using more of a tall window's height instead
## of leaving it blank.
const CARD_COLUMNS := 2

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

	# Issue 53 sweep: this whole column had no scroll container, so at a
	# short viewport (844x390, the phone-landscape size the game is required
	# to work at) the roster's own minimum height -- three rows of 170x200
	# cards -- pushed everything below it, including the Start Fight button,
	# past the bottom of the visible window. A Container does not clip or
	# scroll on its own; the content was still there, just off-canvas, which
	# is exactly "not visible or clickable". The roster is what makes this
	# column tall, so it is what gets the ScrollContainer and the
	# SIZE_EXPAND_FILL that lets it give up space to whatever the viewport
	# actually has -- the seed row, status label and every button below it
	# keep their natural size and stay pinned inside the fixed remainder.
	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(roster_scroll)

	_roster_box = GridContainer.new()
	_roster_box.columns = CARD_COLUMNS
	_roster_box.add_theme_constant_override("h_separation", int(Palette.SPACE_M))
	_roster_box.add_theme_constant_override("v_separation", int(Palette.SPACE_M))
	_roster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(_roster_box)

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

	# Issue 43: a run is several rooms in sequence with damage carried
	# between them, the whole reason Scripts/Floor exists. Kept beside the
	# single-fight button rather than replacing it — the single fight is
	# how the balance actually gets measured (issue 43's own criterion 5).
	_start_run_button = Button.new()
	_start_run_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	_start_run_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	_start_run_button.pressed.connect(_on_start_run_pressed)
	column.add_child(_start_run_button)

	# Issue 21b: reachable from party select, before anyone has committed to a
	# fight — the obvious place to read what a class will actually do before
	# picking it.
	var inspect_button := Button.new()
	inspect_button.text = "Inspect classes"
	inspect_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	inspect_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	inspect_button.pressed.connect(_on_inspect_pressed)
	column.add_child(inspect_button)

	# Issue 19: the room library the generator draws from was five
	# hand-written GDScript rooms; this is where a player grows it. Reachable
	# from here rather than only mid-run, since authoring has nothing to do
	# with the party you are about to fight with.
	var level_editor_button := Button.new()
	level_editor_button.text = "Level editor"
	level_editor_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	level_editor_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	level_editor_button.pressed.connect(func(): level_editor_requested.emit())
	column.add_child(level_editor_button)

	_inspect_panel = Control.new()
	_inspect_panel.set_script(InspectPanelScript)
	add_child(_inspect_panel)
	# Same reasoning as PartyCard's own manual _ready() call above: this node
	# may be built while PartySelect itself is not yet in a live tree (a test
	# calling _ready() directly), and add_child alone only triggers _ready()
	# automatically once the parent enters a real SceneTree.
	if not _inspect_panel.is_inside_tree():
		_inspect_panel._ready()

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
	if _start_run_button != null:
		_start_run_button.disabled = _selected.is_empty()
		_start_run_button.text = "Pick at least one class" if _selected.is_empty() else "Start Run"

func _on_start_pressed() -> void:
	battle_requested.emit(current_config())

func _on_start_run_pressed() -> void:
	run_requested.emit(current_config())

func _on_inspect_pressed() -> void:
	if _inspect_panel != null:
		_inspect_panel.open(_available)

## Issue 32: this picked Registry.all_encounter_ids()[0] — alphabetically
## first, not the encounter the game actually means. CG.DEFAULT_ENCOUNTER
## exists exactly to name that without picking by index; every devtool was
## fixed to use it and this screen, the one an actual player reaches, was
## missed. floor1_ghoul_den sorts before floor1_room1, so every real
## playthrough since encounters plural existed has fought the wrong room —
## wren measured 0 losses in 1000 samples on it.
func current_config() -> RunConfig:
	var config := RunConfig.new()
	config.party = _selected.duplicate()
	var encounters := Registry.all_encounter_ids()
	if encounters.has(CG.DEFAULT_ENCOUNTER):
		config.encounter_id = CG.DEFAULT_ENCOUNTER
	else:
		config.encounter_id = encounters[0] if not encounters.is_empty() else &""
	config.seed = RunConfig.parse_seed(_seed_edit.text) if _seed_edit != null else 0
	return config
