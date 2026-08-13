extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")
const FloorRun := preload("res://Scripts/Floor/FloorRun.gd")
const FloorRoom := preload("res://Scripts/Floor/FloorRoom.gd")
const FloorFightRunner := preload("res://Scripts/Floor/FloorFightRunner.gd")
const LootTables := preload("res://Scripts/Content/LootTables.gd")

## Issue 43: the floor exists (Scripts/Floor/**, wren) and nothing in
## Scripts/UI ever referenced it. This is the smallest thing that makes a
## run a run: see the rooms, enter one, come back with damage carried.
##
## OWNER: pike.
##
## Every room type resolves through FloorFightRunner.play_room or
## play_treasure_room, both already fully public and already correct
## (real difficulty-scaled encounters, real seeded loot rolls) — no new
## API needed. Fight rooms resolve instantly rather than animating live;
## FloorRun.hp_for/is_alive (also already public) are what make the
## carried damage visible afterward, on this same screen, which is the
## thing issue 43 actually asks for. A live animated replay of a floor
## fight is a real future improvement, not a requirement here.

signal run_ended(victory: bool)
signal back_requested

var run: FloorRun = null
var party: Array[PawnData] = []

var _room_buttons: Dictionary = {}
var _map_area: Control = null
var _loot_label: Label = null
var _status_label: Label = null

var _equip_button: Button = null
var _equip_panel: PanelContainer = null
var _equip_list: VBoxContainer = null
## Set while the player is choosing a pawn to receive this item; null means
## the panel is showing the loot list instead.
var _equip_selected_item: EquipmentDef = null

const _ROOM_BUTTON_SIZE := Vector2(140.0, 60.0)
const _COLUMN_SPACING := 170.0
const _ROW_SPACING := 90.0
const _EQUIP_PANEL_WIDTH := 260.0
## Below the title row, status line and loot line so the panel never
## overlaps them — found clipping the header on a real 844x390 launch.
const _EQUIP_PANEL_TOP := 130.0

func _ready() -> void:
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

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", int(Palette.SPACE_M))
	column.add_child(top_row)

	var title := Label.new()
	title.text = "The floor"
	title.add_theme_font_size_override("font_size", Palette.FONT_SIZE_HEADING)
	title.add_theme_color_override("font_color", Palette.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)

	_equip_button = Button.new()
	_equip_button.text = "Equip"
	_equip_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	_equip_button.pressed.connect(_on_equip_pressed)
	top_row.add_child(_equip_button)

	var back_button := Button.new()
	back_button.text = "Change party"
	back_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	back_button.pressed.connect(func(): back_requested.emit())
	top_row.add_child(back_button)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	_status_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_status_label)

	_loot_label = Label.new()
	_loot_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	_loot_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_loot_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_loot_label)

	var map_scroll := ScrollContainer.new()
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(map_scroll)

	_map_area = Control.new()
	_map_area.custom_minimum_size = Vector2(900.0, 400.0)
	map_scroll.add_child(_map_area)

	# Anchored within the screen rather than PRESET_CENTER's unbounded size —
	# a real bug on a short viewport (844x390 landscape): a five-pawn list
	# grew the panel past the bottom edge before this had a height limit.
	_equip_panel = PanelContainer.new()
	_equip_panel.visible = false
	_equip_panel.anchor_left = 1.0
	_equip_panel.anchor_right = 1.0
	_equip_panel.anchor_top = 0.0
	_equip_panel.anchor_bottom = 1.0
	_equip_panel.offset_left = -(_EQUIP_PANEL_WIDTH + Palette.SPACE_L)
	_equip_panel.offset_right = -Palette.SPACE_L
	_equip_panel.offset_top = _EQUIP_PANEL_TOP
	_equip_panel.offset_bottom = -Palette.SPACE_L
	add_child(_equip_panel)

	var equip_margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		equip_margin.add_theme_constant_override("margin_%s" % side, int(Palette.SPACE_L))
	_equip_panel.add_child(equip_margin)

	var equip_scroll := ScrollContainer.new()
	equip_margin.add_child(equip_scroll)

	_equip_list = VBoxContainer.new()
	_equip_list.add_theme_constant_override("separation", int(Palette.SPACE_S))
	equip_scroll.add_child(_equip_list)

func open(new_run: FloorRun, new_party: Array[PawnData]) -> void:
	run = new_run
	party = new_party
	_refresh()

## `message`, when given, replaces the default "You are in" status for this
## refresh only — a real bug, found on a real launch: _on_room_pressed set
## the outcome text ("Cleared the Enemy...") and then called _refresh()
## unconditionally, which immediately overwrote it with the ambient status
## before a player could ever read it. The outcome is the thing "come back
## with damage carried" is actually asking to be visible.
func _refresh(message: String = "") -> void:
	if run == null:
		return
	for id in _room_buttons:
		_room_buttons[id].queue_free()
	_room_buttons.clear()

	var reachable := run.plan.reachable_from_entrance()
	var depth := _depths_from_entrance()
	var per_depth_count: Dictionary = {}

	for room_id in reachable:
		var room := run.plan.room(room_id)
		if room == null:
			continue
		var d: int = depth.get(room_id, 0)
		var row: int = per_depth_count.get(d, 0)
		per_depth_count[d] = row + 1
		_add_room_button(room, d, row)

	if message != "":
		_status_label.text = message
	else:
		_status_label.text = "You are in: %s (%s)" % [
			FloorRoom.type_name(run.plan.room(run.current_room_id).type),
			_party_status_text()
		]
	_loot_label.text = "Loot found: %s" % _loot_text()
	_equip_button.disabled = run.loot.is_empty()
	if _equip_panel.visible:
		_show_equip_panel()

func _party_status_text() -> String:
	var parts: Array[String] = []
	for pawn in party:
		var alive := run.is_alive(pawn.id)
		parts.append("%s%s" % [pawn.display_name, "" if alive else " (down)"])
	return ", ".join(parts)

func _loot_text() -> String:
	if run.loot.is_empty():
		return "nothing yet"
	return ", ".join(run.loot.map(func(item): return item.display_name))

## BFS depth from the entrance, over the *whole* plan (not just reachable),
## since a room past a gate (miniboss/boss) still needs a column even
## before it is reachable-with-the-gate-removed — reachable_from_entrance
## already only returns what is actually reachable; this only decides
## where on screen each of those rooms sits.
func _depths_from_entrance() -> Dictionary:
	var depth: Dictionary = {run.plan.entrance_id: 0}
	var queue: Array[int] = [run.plan.entrance_id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		var room := run.plan.room(current)
		if room == null:
			continue
		for next_id in room.connections:
			if not depth.has(next_id):
				depth[next_id] = depth[current] + 1
				queue.append(next_id)
	return depth

func _add_room_button(room: FloorRoom, column: int, row: int) -> void:
	var button := Button.new()
	button.custom_minimum_size = _ROOM_BUTTON_SIZE
	button.position = Vector2(column * _COLUMN_SPACING, row * _ROW_SPACING)
	button.text = _room_label(room)

	var is_current := room.id == run.current_room_id
	var is_visited := run.visited.has(room.id)
	var is_adjacent := run.plan.room(run.current_room_id) != null \
		and run.plan.room(run.current_room_id).connections.has(room.id)

	# Issue 43 criterion 2: identifiable before entering. The type is
	# always in the button's own text (_room_label), never hidden behind a
	# generic "Room" label — a boss must not be a surprise on arrival.
	if is_current:
		button.add_theme_color_override("font_color", Palette.TEAM_PLAYER)
		button.disabled = true
	elif is_visited:
		button.add_theme_color_override("font_color", Palette.TEXT_DIM)
		button.disabled = true
	elif is_adjacent:
		button.pressed.connect(_on_room_pressed.bind(room))
	else:
		button.disabled = true

	_map_area.add_child(button)
	_room_buttons[room.id] = button

func _room_label(room: FloorRoom) -> String:
	var suffix := ""
	if room.id == run.current_room_id:
		suffix = " (here)"
	elif run.visited.has(room.id):
		suffix = " (cleared)"
	return "%s%s" % [FloorRoom.type_name(room.type), suffix]

func _on_room_pressed(room: FloorRoom) -> void:
	if FloorFightRunner.is_fight_room(room.type):
		# play_room now returns {"outcome": Outcome, "state": CombatState}
		# (wren, per pike's ask) — outcome is still the only thing this
		# screen reads today; state is here for a future live replay.
		var result := FloorFightRunner.play_room(run, room, party)
		var outcome: FloorFightRunner.Outcome = result.outcome
		if outcome == FloorFightRunner.Outcome.DEFEAT:
			run_ended.emit(false)
			return
		if outcome == FloorFightRunner.Outcome.VICTORY:
			run_ended.emit(true)
			return
		_refresh(_outcome_text(outcome, room))
		return
	if room.type == FloorRoom.Type.TREASURE:
		FloorFightRunner.play_treasure_room(run, room)
	else:
		# TRAP/LIBRARY/CELL: no mechanics built yet (issue 43's own scope).
		# Entering is the smallest correct thing — the room becomes
		# visited and the run continues — rather than inventing a trap or
		# library effect nobody asked for.
		run.enter(room.id)
	_refresh()

func _outcome_text(outcome: int, room: FloorRoom) -> String:
	match outcome:
		FloorFightRunner.Outcome.DEFEAT:
			return "Defeated in the %s." % FloorRoom.type_name(room.type)
		FloorFightRunner.Outcome.VICTORY:
			return "Victory! The %s falls." % FloorRoom.type_name(room.type)
		_:
			return "Cleared the %s. %s" % [FloorRoom.type_name(room.type), _party_status_text()]

## Issue 41's routing: "the equip screen, once something can be equipped."
## `run.loot` is the holding pen wren's fights already drop into; this is
## the other half — assign a dropped item to a pawn's slot. No new Core API:
## PawnData's weapon/armor/accessory are already public, and
## EquipmentDef.allows() already says which pawn may wear a piece, so the
## screen only has to ask the question and never has to enforce it twice.
func _on_equip_pressed() -> void:
	_equip_selected_item = null
	_equip_panel.visible = true
	_show_equip_panel()

func _show_equip_panel() -> void:
	for child in _equip_list.get_children():
		child.queue_free()

	if _equip_selected_item == null:
		_populate_loot_list()
	else:
		_populate_pawn_list(_equip_selected_item)

func _populate_loot_list() -> void:
	var heading := Label.new()
	heading.text = "Equip which item?"
	heading.add_theme_color_override("font_color", Palette.TEXT)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD
	heading.custom_minimum_size = Vector2(_EQUIP_PANEL_WIDTH - Palette.SPACE_L * 2.0, 0.0)
	_equip_list.add_child(heading)

	for item in run.loot:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
		button.text = "%s (%s)" % [item.display_name, _slot_name(item.slot)]
		button.pressed.connect(_on_loot_item_pressed.bind(item))
		_equip_list.add_child(button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	close_button.pressed.connect(func(): _equip_panel.visible = false)
	_equip_list.add_child(close_button)

func _populate_pawn_list(item: EquipmentDef) -> void:
	var heading := Label.new()
	heading.text = "Give %s to:" % item.display_name
	heading.add_theme_color_override("font_color", Palette.TEXT)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD
	heading.custom_minimum_size = Vector2(_EQUIP_PANEL_WIDTH - Palette.SPACE_L * 2.0, 0.0)
	_equip_list.add_child(heading)

	for pawn in party:
		var method := CG.Method.MARTIAL
		if pawn.pawn_class != null:
			method = pawn.pawn_class.method
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
		if item.allows(method):
			button.text = pawn.display_name
			button.pressed.connect(_on_pawn_picked.bind(pawn, item))
		else:
			button.text = "%s (cannot use this)" % pawn.display_name
			button.disabled = true
		_equip_list.add_child(button)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	back_button.pressed.connect(func():
		_equip_selected_item = null
		_show_equip_panel()
	)
	_equip_list.add_child(back_button)

func _on_loot_item_pressed(item: EquipmentDef) -> void:
	_equip_selected_item = item
	_show_equip_panel()

func _on_pawn_picked(pawn: PawnData, item: EquipmentDef) -> void:
	match item.slot:
		EquipmentDef.Slot.WEAPON:
			pawn.weapon = item
		EquipmentDef.Slot.ARMOR:
			pawn.armor = item
		EquipmentDef.Slot.ACCESSORY:
			pawn.accessory = item
	run.loot.erase(item)
	_equip_selected_item = null
	_equip_panel.visible = false
	_refresh()

func _slot_name(slot: EquipmentDef.Slot) -> String:
	match slot:
		EquipmentDef.Slot.WEAPON:
			return "weapon"
		EquipmentDef.Slot.ARMOR:
			return "armor"
		_:
			return "accessory"
