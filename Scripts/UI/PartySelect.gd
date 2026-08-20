extends Control
class_name PartySelect

const PartyCardScript := preload("res://Scripts/UI/PartyCard.gd")
const InspectPanelScript := preload("res://Scripts/UI/InspectPanel.gd")
const EquipPanelScript := preload("res://Scripts/UI/EquipPanel.gd")
const SCENE := "res://Scenes/PartySelect.tscn"

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
	for class_id in Registry.all_class_ids():
		var cls: ClassDef = Registry.get_class_def(class_id)
		if cls == null:
			continue
		_available.append(PawnFactory.make_starter_pawn(class_id, class_id, cls.display_name))

## Registered encounters the picker does not offer, with the reason. Offered
## rooms are not listed here: `Encounter.pickable` is set where the room is
## declared and `offered_rooms()` reads it, in module order.
##
## The rule: offer any room whose point is a fight and which nothing else can
## reach; exclude tuning fixtures. `floor1_warden` returns here on the day a
## player can reach it by progressing (#300).
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
##
## **The chrome around them is in `Scenes/PartySelect.tscn` and is edited there,
## not here.** The margins, spacings, font sizes and dim colours in that file are
## literals rather than reads of `Palette`, deliberately: re-applying `Palette`
## at runtime would silently overwrite whatever the scene was edited to say,
## which is the whole reason the tree moved out of code.
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

	_seed_edit.text = "%08X" % (randi() & 0xFFFFFFFF)
	_seed_edit.add_theme_stylebox_override("normal", _seed_box_style())
	_seed_edit.add_theme_stylebox_override("focus", _seed_box_style())

	_room_picker.item_selected.connect(func(_i: int): _refresh_room_summary())
	_start_button.pressed.connect(_on_start_pressed)
	_start_run_button.pressed.connect(_on_start_run_pressed)
	# Issue 21b: reachable before anyone has committed to a fight. Issue 100:
	# equipment beside the plan editor rather than inside it -- the two screens
	# answer different questions about the same pawn, and a granted skill is the
	# seam. Issue 19: the level editor is where a player grows the room library,
	# which has nothing to do with the party they are about to fight with.
	%InspectButton.pressed.connect(_on_inspect_pressed)
	%EquipButton.pressed.connect(_on_equip_pressed)
	%LevelEditorButton.pressed.connect(func(): level_editor_requested.emit())

	_inspect_panel = _add_panel(InspectPanelScript)
	# Added after the inspect panel so it draws above it if both are ever open.
	_equip_panel = _add_panel(EquipPanelScript)

## **A panel whose tree has moved into a `.tscn` cannot be built by setting the
## script on a bare Control**: it gets none of the tree, `%Name` resolves to
## nothing, and `_ready()` aborts on the first one -- a blank screen behind a
## green test suite, because a detached screen never renders. `create()` is the
## constructor those panels expose.
##
## InspectPanel and EquipPanel are moving to scenes on other sessions' branches,
## so this asks rather than assuming and builds correctly whichever lands first.
## **Delete the second half and call `create()` directly once both are on the
## trunk** -- it is a merge-order accommodation, not a pattern.
##
## The manual `_ready()` is the same reasoning as PartyCard's in `_fill_roster`:
## this node may be built while PartySelect is not yet in a live tree (a test
## calling `_ready()` directly), and `add_child` alone only triggers `_ready()`
## automatically once the parent enters a real SceneTree.
func _add_panel(script) -> Control:
	var panel: Control
	if script.has_method("create"):
		panel = script.create()
	else:
		panel = Control.new()
		panel.set_script(script)
	add_child(panel)
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
		var room = Registry.get_encounter(id)
		_room_picker.add_item(room.display_name if room.display_name != "" else String(id))
		_room_picker.set_item_metadata(_room_picker.item_count - 1, id)
		if id == CG.DEFAULT_ENCOUNTER:
			_room_picker.selected = _room_picker.item_count - 1

## A bordered box, not a bare underline, so it reads as an editable field
## rather than a label — issue 17's "the seed control should look like
## something you can edit".
##
## **Deliberately NOT routed through `UIArt.panel_style` by issue 268**, which
## routed the other four hand-built styles in `Scripts/UI`. The README promises
## `panel.png` re-skins "every panel, card, tooltip and chip" and this is none
## of those: it is an input. Its border is carrying information — issue 17's
## whole point is that it says *you can type here* — and a dropped-in `panel.png`
## would draw it identically to every static panel on the screen and take that
## away, which is the `PartyCard` rule and would look perfectly fine in a
## screenshot. If the seed field is ever meant to be themable it needs its own
## documented name, not the panel one.
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

func _on_inspect_pressed() -> void:
	if _inspect_panel != null:
		_inspect_panel.open(_available)

## `_available`, the same instances `current_config()` puts into
## `RunConfig.party` -- so equipping a pawn here equips the pawn that fights,
## with no apply step. The plan editor is opened the same way and for the same
## reason.
func _on_equip_pressed() -> void:
	if _equip_panel != null:
		_equip_panel.open(_available)

## Issue 32: this picked Registry.all_encounter_ids()[0] — alphabetically
## first, not the encounter the game actually means. CG.DEFAULT_ENCOUNTER
## exists exactly to name that without picking by index; every devtool was
## fixed to use it and this screen, the one an actual player reaches, was
## missed. floor1_ghoul_den sorts before floor1_room1, so every real
## playthrough since encounters plural existed has fought the wrong room —
## wren measured 0 losses in 1000 samples on it.
## Issue 176: the room the player picked, defaulting to `CG.DEFAULT_ENCOUNTER`.
##
## **The issue-32 protection above is kept, not replaced.** That fix was correct
## and it also became a lid: it pinned the game to one room and nobody re-read
## it when three more arrived, so four days of enemies and terrain shipped
## unreachable. The rule it encodes -- never pick an encounter by index, because
## `Array[StringName].sort()` orders by interned pointer and `floor1_ghoul_den`
## sorts before `floor1_room1` -- is still live and still right. It now applies
## to the *fallback* rather than to every case.
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
	var encounters := Registry.all_encounter_ids()
	if encounters.has(CG.DEFAULT_ENCOUNTER):
		return CG.DEFAULT_ENCOUNTER
	return encounters[0] if not encounters.is_empty() else &""

## Rooms the picker offers: every registered encounter whose content sets
## `pickable`, in registration order rather than sorted -- `Array[StringName]`
## does not sort alphabetically and the order a player reads should not depend
## on which StringNames the process interned first.
##
## Issue #180. This used to filter a `ROOM_ORDER` constant down to the rooms that
## exist; the flag cannot name a room that does not exist, so the filter is gone
## with it. **The cost, stated because a comment in `test_ui_room_picker.gd`
## relied on it:** a room can no longer be classified before its content lands,
## because the classification is now part of the content. They merge together or
## not at all.
static func offered_rooms() -> Array[StringName]:
	return Registry.pickable_encounter_ids()

func _refresh_room_summary() -> void:
	if _room_summary == null:
		return
	_room_summary.text = room_summary(selected_room())

## Derived from the `Encounter`, never authored beside it. A hand-written blurb
## is a second artifact that goes quietly false the day somebody moves a pillar;
## this cannot, because it is counting the real thing the fight will use.
static func room_summary(id: StringName) -> String:
	var room = Registry.get_encounter(id)
	if room == null:
		return ""
	var parts: Array[String] = ["%d enemies" % room.enemy_spawns.size()]
	var counts := {}
	for feature in room.terrain:
		counts[feature.kind] = int(counts.get(feature.kind, 0)) + 1
	for kind in [Terrain.Kind.WALL, Terrain.Kind.PILLAR, Terrain.Kind.HAZARD, Terrain.Kind.PIT]:
		if counts.has(kind):
			parts.append("%d %s" % [counts[kind], TERRAIN_WORDS[kind][0 if counts[kind] == 1 else 1]])
	if parts.size() == 1:
		parts.append("open ground")
	return " · ".join(parts)
