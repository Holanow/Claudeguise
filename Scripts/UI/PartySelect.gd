extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const UIArt := preload("res://Scripts/Art/UIArt.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const PartyCardScript := preload("res://Scripts/UI/PartyCard.gd")
const InspectPanelScript := preload("res://Scripts/UI/InspectPanel.gd")
const EquipPanelScript := preload("res://Scripts/UI/EquipPanel.gd")
const GlossaryButtonScript := preload("res://Scripts/UI/GlossaryButton.gd")

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

## Issue 18: rook's own eyeballed read of party_select_phone_400x800.png was
## "every card well under the 48-pixel touch minimum". Measured instead with
## get_global_rect() (Control's coordinates are always logical, the same as
## custom_minimum_size — the stretch scale is applied at render/input-mapping
## time, not by resizing controls): every card is 170x200, over three times
## TOUCH_TARGET_MIN on its short side, at any window size. Godot maps a real
## tap back through the same stretch transform, so this is the actual
## functional target, not merely a number that happens not to shrink.
##
## **Issue 133 replaced the fixed `CARD_COLUMNS = 2` grid with an
## `HFlowContainer`, and the argument that column count had to be fixed was
## wrong in a way worth keeping written down.** It ran: `expand` stretch means
## `get_viewport_rect()` reports design space rather than physical pixels, so a
## container computing its own columns from the viewport cannot get narrower on
## a phone. That is true of `get_viewport_rect()` and it is not an argument for
## a constant, because **a flow container does not ask the viewport anything.**
## It wraps at the width its parent gives it, which is a real layout width in
## the same logical space every other Control here uses. So the responsive case
## and the wide case are one behaviour rather than two competing schemes, which
## is what the old comment was right to want.
##
## The cost of the constant was the player's complaint: five classes, room for
## all five, showing two, in the left quarter of a 1280-wide screen, clipped
## mid-row inside a scroll box.
## Issue 176 -- THE FOUR ROOMS THE PICKER OFFERS, and why this list lives here.
##
## The four are named in prose in `floor1_encounters.gd` and in a `PICKABLE`
## constant inside a test, and nowhere a program can read. Rather than add a
## third hand-written copy that can quietly disagree with the other two,
## `test_ui_room_picker.gd` asserts that **every registered encounter is either
## offered here or listed in `NOT_OFFERED` with a reason.** A new room therefore
## cannot appear without somebody deciding which it is -- which is exactly the
## failure this issue is: three rooms, four days of enemies and terrain, and
## nothing anywhere noticed they were unreachable.
##
## Authored order, not sorted: `Array[StringName].sort()` compares interned
## pointers rather than text, so a sorted list would present rooms in an order
## that depends on process history.
## **`ROOM_ORDER` is not #94's "four comparable rooms" and the two must not be
## confused, because they answer different questions.** `PICKABLE` in
## `test_content_rooms.gd` is the set that has to field the same headcount so
## layout and roster stay comparable; this is the set a player can select. The
## Rat King is in the second and deliberately not the first -- heron's own
## reasoning, and the same reason `floor1_warden` fields one enemy.
const ROOM_ORDER: Array[StringName] = [
	&"floor1_room1",
	&"floor1_cover",
	&"floor1_hazard",
	&"floor1_chokepoint",
	&"floor1_rat_king",
	&"floor1_warden",
]

## Registered encounters the picker deliberately does not offer, with the
## reason.
##
## **THE RULE, written down because the next boss hits the same fork.** Offer any
## room whose point is a fight and which nothing else can reach. Exclude tuning
## fixtures, which the tools fight directly and a player has no reason to meet.
## It used to exclude the floor's terminal boss as well, whose point is *arrival*
## rather than the fight itself; see the ruling below for why that half is
## suspended and when it comes back.
##
## The Rat King is offered on that rule: **nothing about runs exists yet**, so
## "a single fight you can pick" and "a miniboss you progress to" are not two
## different things in the game, only in intent -- and excluding it would ship
## the King, the rats, BLEED stacking and sable's silhouette unreachable, which
## is the exact failure #176 existed to end.
##
## **The terminal-boss half of the rule is suspended, by the player's ruling on
## #194: "if the warden is done and ready to go I see no reason not to make it
## playable".** The reasoning it overrules -- that offering the floor boss off a
## menu spends its arrival once and for free -- is not wrong; it is beaten by the
## simpler fact that **there is no floor to arrive at.** The Warden is the
## most-measured content in this game and no player has ever fought it, which is
## #176's failure again with a better excuse attached.
##
## **The exclusion returns when runs exist.** Keep this paragraph and move
## `floor1_warden` back into `NOT_OFFERED` on the day a player can reach it by
## progressing. Until then the rule reads: offer any room whose point is a fight
## and which nothing else can reach; exclude tuning fixtures only.
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

func _build_ui() -> void:
	# Issue 237. One line instead of three, and the point is not the two lines:
	# `Assets/UI/README.md` promises the player that dropping in
	# `background/party_select.png` (or `background.png` for every screen at once)
	# re-skins this screen, and until this call existed it did nothing at all.
	# With no file present `background_node` returns exactly the ColorRect this
	# replaced, in exactly this colour, so nothing shipped changes.
	add_child(UIArt.background_node(&"party_select", Palette.BACKGROUND))

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

	# Issue 133, straight from the player: "The opening screen has a ton of
	# horizontal space to use but I still have to scroll the class selector.
	# Make it fill the available space instead."
	#
	# A ScrollContainer hands its child the child's own minimum width and lets
	# it scroll sideways, which would let the flow put all five cards on one
	# line and scroll rather than wrap. Disabling horizontal scrolling makes the
	# ScrollContainer force the flow to its own width, which is the width the
	# window actually has -- so the wrap point comes from the layout instead of
	# from a number anybody typed.
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_roster_box = HFlowContainer.new()
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

	# Issue 176: the room picker. Above the seed, because which room you fight is
	# a bigger decision than which seed you fight it on.
	var room_row := HBoxContainer.new()
	room_row.add_theme_constant_override("separation", int(Palette.SPACE_S))
	column.add_child(room_row)

	var room_label := Label.new()
	room_label.text = "Room"
	room_label.custom_minimum_size = Vector2(48.0, 0.0)
	room_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	room_label.add_theme_color_override("font_color", Palette.TEXT)
	room_row.add_child(room_label)

	_room_picker = OptionButton.new()
	_room_picker.custom_minimum_size = Vector2(320.0, Palette.TOUCH_TARGET_MIN)
	_room_picker.fit_to_longest_item = false
	_room_picker.clip_text = true
	_room_picker.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	for id in offered_rooms():
		var room = Registry.get_encounter(id)
		_room_picker.add_item(room.display_name if room.display_name != "" else String(id))
		_room_picker.set_item_metadata(_room_picker.item_count - 1, id)
		if id == CG.DEFAULT_ENCOUNTER:
			_room_picker.selected = _room_picker.item_count - 1
	_room_picker.item_selected.connect(func(_i: int): _refresh_room_summary())
	room_row.add_child(_room_picker)

	# What the room is, derived from the room rather than authored beside it, so
	# it cannot drift from what the fight actually contains. The playtest found
	# that nothing anywhere explains anything; a name alone would repeat that.
	_room_summary = Label.new()
	_room_summary.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	_room_summary.add_theme_color_override("font_color", Palette.TEXT_DIM)
	room_row.add_child(_room_summary)
	_refresh_room_summary()

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

	# PLAYTEST-NOTES 11 / hover-info-box system: "Start Fight and Start Run
	# don't say what they do." Same mechanism as every other glossary term
	# (GlossaryButton, same set_script pattern GlossaryLabel already uses)
	# rather than a second system for two buttons specifically.
	_start_button = Button.new()
	_start_button.set_script(GlossaryButtonScript)
	_start_button.tooltip_text = "Runs one fight with the current party and seed, right now."
	_start_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	_start_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	_start_button.pressed.connect(_on_start_pressed)
	column.add_child(_start_button)

	# Issue 43: a run is several rooms in sequence with damage carried
	# between them, the whole reason Scripts/Floor exists. Kept beside the
	# single-fight button rather than replacing it — the single fight is
	# how the balance actually gets measured (issue 43's own criterion 5).
	_start_run_button = Button.new()
	_start_run_button.set_script(GlossaryButtonScript)
	_start_run_button.tooltip_text = "Enters the floor with the current party. Fights and rooms follow in sequence, with damage and resources carried between them."
	# Issue 133: the four secondary destinations share one wrapping row instead
	# of each taking a full-width band.
	#
	# This is the other half of the player's complaint and it is the half that
	# actually stops the scrolling. Five stacked buttons at TOUCH_TARGET_MIN
	# apiece spent about 320 of 720 pixels of height, each one 1200 pixels wide
	# to hold two words -- so the roster was left 175 pixels for a 200-pixel
	# card and clipped it, and widening the roster alone could not have fixed
	# that. Flowing these frees the height the cards were missing.
	#
	# Start Fight stays a full-width band on its own above this row. It is the
	# primary action and the only one that is not a detour, and evening the five
	# out would have made the screen read as five equal choices.
	var secondary_row := HFlowContainer.new()
	secondary_row.add_theme_constant_override("h_separation", int(Palette.SPACE_M))
	secondary_row.add_theme_constant_override("v_separation", int(Palette.SPACE_S))
	column.add_child(secondary_row)

	_start_run_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	_start_run_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	_start_run_button.pressed.connect(_on_start_run_pressed)
	secondary_row.add_child(_start_run_button)

	# Issue 21b: reachable from party select, before anyone has committed to a
	# fight — the obvious place to read what a class will actually do before
	# picking it.
	var inspect_button := Button.new()
	inspect_button.text = "Inspect classes"
	inspect_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	inspect_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	inspect_button.pressed.connect(_on_inspect_pressed)
	secondary_row.add_child(inspect_button)

	# Issue 100: equipment before the fight, beside the plan editor rather than
	# inside it. The two screens answer different questions about the same pawn
	# -- what it can do, and what it will do -- and a granted skill is the seam:
	# equip Plate Mail here and Directional Block is a block to plan with there.
	var equip_button := Button.new()
	equip_button.text = "Equip pawns"
	equip_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	equip_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	equip_button.pressed.connect(_on_equip_pressed)
	secondary_row.add_child(equip_button)

	# Issue 19: the room library the generator draws from was five
	# hand-written GDScript rooms; this is where a player grows it. Reachable
	# from here rather than only mid-run, since authoring has nothing to do
	# with the party you are about to fight with.
	var level_editor_button := Button.new()
	level_editor_button.text = "Level editor"
	level_editor_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	level_editor_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	level_editor_button.pressed.connect(func(): level_editor_requested.emit())
	secondary_row.add_child(level_editor_button)

	_inspect_panel = Control.new()
	_inspect_panel.set_script(InspectPanelScript)
	add_child(_inspect_panel)
	# Same reasoning as PartyCard's own manual _ready() call above: this node
	# may be built while PartySelect itself is not yet in a live tree (a test
	# calling _ready() directly), and add_child alone only triggers _ready()
	# automatically once the parent enters a real SceneTree.
	if not _inspect_panel.is_inside_tree():
		_inspect_panel._ready()

	# Added after the inspect panel so it draws above it if both are ever open.
	# Same manual _ready() reasoning as every other panel built here.
	_equip_panel = Control.new()
	_equip_panel.set_script(EquipPanelScript)
	add_child(_equip_panel)
	if not _equip_panel.is_inside_tree():
		_equip_panel._ready()

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

## Rooms the picker offers, in a fixed authored order rather than sorted --
## `Array[StringName].sort()` is not alphabetical and the order a player reads
## should not depend on which StringNames the process interned first.
static func offered_rooms() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ROOM_ORDER:
		if Registry.get_encounter(id) != null:
			out.append(id)
	return out

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
