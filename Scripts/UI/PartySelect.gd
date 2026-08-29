extends Control
class_name PartySelect

const PartyCardScript := preload("res://Scripts/UI/PartyCard.gd")
const InspectPanelScript := preload("res://Scripts/UI/InspectPanel.gd")
const EquipPanelScript := preload("res://Scripts/UI/EquipPanel.gd")
const SCENE := "res://Scenes/PartySelect.tscn"

## Pick up to four pawns and a seed, then start the fight.

signal battle_requested(config: RunConfig)
signal run_requested(config: RunConfig)

const MAX_PARTY_SIZE := 4

var _available: Array[PawnData] = []
var _selected: Array[PawnData] = []
var _cards: Dictionary = {}

## Issue 131: the seed the pawns on screen were rolled from. Kept rather than
## re-read off the field, so a half-typed seed cannot reroll under the player.
var _roster_seed := 0

var _status_label: Label = null
var _room_picker: OptionButton = null
var _room_summary: Label = null
var _start_button: Button = null
var _start_run_button: Button = null
var _seed_edit: LineEdit = null
var _roster_box = null
var _inspect_panel = null
var _equip_panel = null

## The tree this screen needs lives in `Scenes/PartySelect.tscn`; `new()` gives a
## bare Control with none of it. Always build this screen with `create()`.
static func create() -> PartySelect:
	return (load(SCENE) as PackedScene).instantiate() as PartySelect

func _ready() -> void:
	theme = AppTheme.shared()
	## Issue 131: the seed is chosen before the roster, not after. A generated
	## pawn's attributes are rolled from it, so a roster built first would
	## belong to a seed the screen never shows.
	_roster_seed = randi() & 0x7FFFFFFF
	_build_roster()
	_bind_ui()
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
	for class_id in ClassLibrary.all_ids():
		var cls: ClassDef = ClassLibrary.get_class_def(class_id)
		if cls == null:
			continue
		_available.append(PawnFactory.make_rolled_pawn(class_id, class_id, cls.display_name, _roster_seed))

## Registered encounters the picker does not offer, with the reason. Offered
## rooms are not listed here: `Encounter.pickable` is set where the room is
## declared and `offered_rooms()` reads it, in module order.
const NOT_OFFERED := {
	&"floor1_horde": "a tuning fixture, not one of issue 94's four comparable rooms",
	&"floor1_ghoul_den": "a tuning fixture, and the room issue 32's bug used to fight by accident",
}

const TERRAIN_WORDS := {
	Terrain.Kind.WALL: ["wall", "walls"],
	Terrain.Kind.PILLAR: ["pillar", "pillars"],
	Terrain.Kind.HAZARD: ["burn band", "burn bands"],
	Terrain.Kind.PIT: ["pit", "pits"],
}

## Everything a scene file cannot express: the art-swappable background, the
## per-class cards and per-room picker items (both loops), the panels built by
## `set_script`, and every signal connection.
func _bind_ui() -> void:
	# Issue 237. `Assets/UI/README.md` promises the player that dropping in
	# `background/party_select.png` (or `background.png` for every screen at once)
	# re-skins this screen. With no file present `background_node` returns exactly
	# a ColorRect in `Palette.BACKGROUND`. Built here rather than in the scene
	# because which node it is depends on whether that file exists; moved to index
	# 0 because it has to draw behind the tree the scene already brought.
	var background := UIArt.background_node(&"party_select", Palette.BACKGROUND)
	add_child(background)
	move_child(background, 0)

	_roster_box = %RosterBox
	_room_picker = %RoomPicker
	_room_summary = %RoomSummary
	_seed_edit = %SeedEdit
	_status_label = %StatusLabel
	_start_button = %StartButton
	_start_run_button = %StartRunButton

	_fill_roster()
	_fill_rooms()
	_refresh_room_summary()

	_seed_edit.text = "%08X" % _roster_seed
	## Issue 131: retyping a seed rebuilds the roster, which is how a player
	## reproduces a roll they liked. Submit rather than every keystroke: a
	## half-typed seed is not a seed.
	_seed_edit.text_submitted.connect(func(t: String): reroll_from_seed(t))
	_seed_edit.add_theme_stylebox_override("normal", _seed_box_style())
	_seed_edit.add_theme_stylebox_override("focus", _seed_box_style())

	_room_picker.item_selected.connect(func(_i: int): _refresh_room_summary())
	_start_button.pressed.connect(_on_start_pressed)
	_start_run_button.pressed.connect(_on_start_run_pressed)

	## Issue 351. Both panels live in the middle column rather than over the top
	## of the screen, so the plan budget and the WIS that sets it are one glance
	## apart.
	_inspect_panel = _add_panel(InspectPanelScript, %MiddleColumn)
	_inspect_panel.embed()
	_inspect_panel.size_flags_stretch_ratio = 3.0
	_equip_panel = _add_panel(EquipPanelScript, %MiddleColumn)
	_equip_panel.embed()
	_equip_panel.size_flags_stretch_ratio = 2.0
	## WIS bought by an item changes the plan budget, and the row it un-inerts is
	## on screen at the time.
	_equip_panel.equipment_changed.connect(func(pawn): _inspect_panel.show_pawn(pawn))
	focus_pawn(_available[0] if not _available.is_empty() else null)

## **A panel whose tree has moved into a `.tscn` cannot be built by setting the
## script on a bare Control**: it gets none of the tree, `%Name` resolves to
## nothing, and `_ready()` aborts on the first one -- a blank screen behind a
## green test suite, because a detached screen never renders. `create()` is the
## constructor those panels expose.
func _add_panel(script, parent: Node = null) -> Control:
	var panel: Control
	if script.has_method("create"):
		panel = script.create()
	else:
		panel = Control.new()
		panel.set_script(script)
	(parent if parent != null else self).add_child(panel)
	if not panel.is_inside_tree():
		panel._ready()
	return panel

## One card per class, so it stays in code. Issue 17: a checkbox next to a bare
## class name did not let anyone make this screen's only decision; each class is
## a PartyCard showing its silhouette, role and style, and the whole card is the
## touch target (measured at 170x200, over three times TOUCH_TARGET_MIN).
func _fill_roster() -> void:
	if _available.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No classes available yet."
		empty_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_roster_box.add_child(empty_label)
		return
	for pawn in _available:
		var card := Control.new()
		card.set_script(PartyCardScript)
		# Called directly rather than left to the engine: this node may be built
		# while PartySelect itself is not yet in a live tree (a test calling
		# _ready() directly), and custom_minimum_size has to be set either way
		# for the touch-target guarantee to hold.
		card._ready()
		card.class_def = pawn.pawn_class
		card.toggled.connect(_on_card_toggled.bind(pawn))
		_roster_box.add_child(card)
		_cards[pawn.id] = card

## Issue 176: one item per offered room, so it stays in code.
func _fill_rooms() -> void:
	for id in offered_rooms():
		var room = RoomLibrary.get_room(id)
		_room_picker.add_item(room.display_name if room.display_name != "" else String(id))
		_room_picker.set_item_metadata(_room_picker.item_count - 1, id)
		if id == CG.DEFAULT_ENCOUNTER:
			_room_picker.selected = _room_picker.item_count - 1

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

## A card decides party membership and who the middle column is about, and the
## second happens even when the first is refused.
func _on_card_toggled(pressed: bool, pawn: PawnData) -> void:
	focus_pawn(pawn)
	if pressed and _selected.size() >= MAX_PARTY_SIZE and not _selected.has(pawn):
		_flash_party_full()
		return
	toggle_pawn(pawn, pressed)

## Who the middle column is showing.
var _focused: PawnData = null

func focus_pawn(pawn: PawnData) -> void:
	_focused = pawn
	if pawn == null:
		return
	if _inspect_panel != null:
		## Issue 755: "stand near ally" offers the party the fight will
		## actually have, not the whole rolled roster.
		_inspect_panel.set_party_roster(_selected)
		_inspect_panel.show_pawn(pawn)
	if _equip_panel != null:
		_equip_panel.show_pawn(pawn)

func focused_pawn() -> PawnData:
	return _focused

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
	## Issue 131: adopt the seed without rebuilding. `restore_roster` has
	## already handed back the pawns this seed rolled, and rebuilding them
	## would throw away the plans and gear #380 exists to keep.
	_roster_seed = RunConfig.parse_seed(seed_text) & 0x7FFFFFFF

## Issue 131: build the roster again from a seed the player typed. Never called
## by `restore_roster`, whose whole job (#380) is to hand the same pawn objects
## back with the plans and gear already on them.
func reroll_from_seed(seed_text: String) -> void:
	var next := RunConfig.parse_seed(seed_text) & 0x7FFFFFFF
	if next == _roster_seed:
		return
	_roster_seed = next
	_build_roster()
	_selected.clear()
	_cards.clear()
	if _roster_box != null:
		for child in _roster_box.get_children():
			_roster_box.remove_child(child)
			child.queue_free()
		_fill_roster()
	_update_status()

## Issue 380. "Change party" swaps in a new PartySelect and `_ready()` rebuilds
## every pawn, so the plans, gear and party the player just wrote were thrown
## away. `Main` keeps the roster and hands the same objects back, which is what
## the seed has always done.
func restore_roster(pawns: Array[PawnData]) -> void:
	if pawns.is_empty():
		return
	_available = pawns.duplicate()
	_selected.clear()
	_cards.clear()
	for child in _roster_box.get_children():
		_roster_box.remove_child(child)
		child.queue_free()
	_fill_roster()
	_update_status()
	focus_pawn(_available[0])

## Matched by identity, not by id: the point is that these are the same objects
## the player edited, so a pawn from anywhere else does not belong here.
func restore_selection(pawns: Array[PawnData]) -> void:
	for pawn in pawns:
		if _available.has(pawn):
			toggle_pawn(pawn, true)

func select_room(id: StringName) -> void:
	if _room_picker == null:
		return
	for i in _room_picker.item_count:
		if _room_picker.get_item_metadata(i) == id:
			_room_picker.selected = i
			_refresh_room_summary()
			return

func _update_status() -> void:
	if _status_label != null:
		_status_label.text = "Party: %d/%d" % [_selected.size(), MAX_PARTY_SIZE]
		_status_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	if _start_button != null:
		_start_button.disabled = _selected.is_empty()
		# rook found this on a real 844x390 launch: both buttons read "Pick
		# at least one class" while disabled and were literally
		# indistinguishable, which is the disabled-state version of the
		# player's own complaint that these two buttons don't say what they
		# do. Each now names its own screen even while disabled.
		_start_button.text = "Pick a party to fight" if _selected.is_empty() else "Start Fight"
	if _start_run_button != null:
		_start_run_button.disabled = _selected.is_empty()
		_start_run_button.text = "Pick a party for a run" if _selected.is_empty() else "Start Run"

func _on_start_pressed() -> void:
	battle_requested.emit(current_config())

func _on_start_run_pressed() -> void:
	run_requested.emit(current_config())

## Issue 32: this picked RoomLibrary.all_ids()[0] — alphabetically
## first, not the encounter the game actually means. CG.DEFAULT_ENCOUNTER
## exists exactly to name that without picking by index; every devtool was
## fixed to use it and this screen, the one an actual player reaches, was
## missed. floor1_ghoul_den sorts before floor1_room1, so every real
## playthrough since encounters plural existed has fought the wrong room —
## wren measured 0 losses in 1000 samples on it.
func current_config() -> RunConfig:
	var config := RunConfig.new()
	config.party = _selected.duplicate()
	config.encounter_id = selected_room()
	config.seed = RunConfig.parse_seed(_seed_edit.text) if _seed_edit != null else 0
	return config

## The picker's current room, or the default when there is no picker yet (a test
## calling `current_config()` on a bare screen) or the metadata is missing.
## Never `all_encounter_ids()[0]` -- see the note above.
func selected_room() -> StringName:
	if _room_picker != null and _room_picker.selected >= 0:
		var id = _room_picker.get_item_metadata(_room_picker.selected)
		if id != null and id != &"":
			return id
	var encounters := RoomLibrary.all_ids()
	if encounters.has(CG.DEFAULT_ENCOUNTER):
		return CG.DEFAULT_ENCOUNTER
	return encounters[0] if not encounters.is_empty() else &""

## Rooms the picker offers: every registered encounter whose content sets
## `pickable`, in registration order rather than sorted -- `Array[StringName]`
static func offered_rooms() -> Array[StringName]:
	return RoomLibrary.pickable_ids()

func _refresh_room_summary() -> void:
	if _room_summary == null:
		return
	_room_summary.text = room_summary(selected_room())

## Derived from the `Encounter`, never authored beside it. A hand-written blurb
## is a second artifact that goes quietly false the day somebody moves a pillar;
## this cannot, because it is counting the real thing the fight will use.
static func room_summary(id: StringName) -> String:
	var room = RoomLibrary.get_room(id)
	if room == null:
		return ""
	var parts: Array[String] = ["%d enemies" % room.enemy_spawns.size()]
	var counts := {}
	for cell in room.cells.values():
		counts[cell.kind] = int(counts.get(cell.kind, 0)) + 1
	for kind in [Terrain.Kind.WALL, Terrain.Kind.PILLAR, Terrain.Kind.HAZARD, Terrain.Kind.PIT]:
		if counts.has(kind):
			parts.append("%d %s" % [counts[kind], TERRAIN_WORDS[kind][0 if counts[kind] == 1 else 1]])
	if parts.size() == 1:
		parts.append("open ground")
	return " · ".join(parts)
