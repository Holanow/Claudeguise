extends Control
class_name FloorMapView


## Issue 43: the floor exists (Scripts/Floor/**, wren) and nothing in
## Scripts/UI ever referenced it. This is the smallest thing that makes a
## run a run: see the rooms, enter one, come back with damage carried.

signal run_ended(victory: bool)
signal back_requested

var run: FloorRun = null
var party: Array[PawnData] = []

var _room_buttons: Dictionary = {}

## Set while the player is choosing a pawn to receive this item; null means
## the panel is showing the loot list instead.
var _equip_selected_item: EquipmentDef = null

## The CELL room currently being resolved, so a candidate button (built
## fresh each time the panel opens) knows which room to pass back to
## resolve_cell. Null whenever the panel is closed.
var _cell_room: FloorRoom = null

const _ROOM_BUTTON_SIZE := Vector2(140.0, 60.0)
const _COLUMN_SPACING := 170.0
const _ROW_SPACING := 90.0
const _EQUIP_PANEL_WIDTH := 260.0
## Below the title row, status line and loot line so the panel never
## overlaps them — found clipping the header on a real 844x390 launch.
const _EQUIP_PANEL_TOP := 130.0

## `new()` gives a bare Control with none of the tree. The chrome lives in
## `Scenes/FloorMap.tscn`; only the room buttons are built here, per room.
static func create() -> FloorMapView:
	return (load("res://Scenes/FloorMap.tscn") as PackedScene).instantiate()

func _ready() -> void:
	theme = AppTheme.shared()
	# Issue 237. One line instead of three, and the point is not the two lines:
	var background := UIArt.background_node(&"floor_map", Palette.BACKGROUND)
	add_child(background)
	move_child(background, 0)

	%EquipButton.pressed.connect(_on_equip_pressed)
	%BackButton.pressed.connect(func(): back_requested.emit())

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
		%StatusLabel.text = message
	else:
		%StatusLabel.text = "You are in: %s (%s)" % [
			FloorRoom.type_name(run.plan.room(run.current_room_id).type),
			_party_status_text()
		]
	%LootLabel.text = "Loot found: %s" % _loot_text()
	%EquipButton.disabled = run.loot.is_empty()
	if %EquipPanel.visible:
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

	%MapArea.add_child(button)
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
	elif room.type == FloorRoom.Type.CELL:
		_on_cell_room_entered(room)
		return
	else:
		# TRAP/LIBRARY: no mechanics built yet (issue 43's own scope).
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
func _on_equip_pressed() -> void:
	_equip_selected_item = null
	%EquipPanel.visible = true
	_show_equip_panel()

func _show_equip_panel() -> void:
	for child in %EquipList.get_children():
		child.queue_free()

	if _equip_selected_item == null:
		_populate_loot_list()
	else:
		_populate_pawn_list(_equip_selected_item)

func _populate_loot_list() -> void:
	var heading := Label.new()
	heading.text = "Equip which item?"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD
	heading.custom_minimum_size = Vector2(_EQUIP_PANEL_WIDTH - Palette.SPACE_L * 2.0, 0.0)
	%EquipList.add_child(heading)

	for item in run.loot:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
		button.text = "%s (%s)" % [item.display_name, _slot_name(item.slot)]
		button.pressed.connect(_on_loot_item_pressed.bind(item))
		%EquipList.add_child(button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	close_button.pressed.connect(func(): %EquipPanel.visible = false)
	%EquipList.add_child(close_button)

func _populate_pawn_list(item: EquipmentDef) -> void:
	var heading := Label.new()
	heading.text = "Give %s to:" % item.display_name
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD
	heading.custom_minimum_size = Vector2(_EQUIP_PANEL_WIDTH - Palette.SPACE_L * 2.0, 0.0)
	%EquipList.add_child(heading)

	for pawn in party:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
		if item.allows_class(pawn.pawn_class):
			button.text = pawn.display_name
			button.pressed.connect(_on_pawn_picked.bind(pawn, item))
		else:
			button.text = "%s (cannot use this)" % pawn.display_name
			button.disabled = true
		%EquipList.add_child(button)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	back_button.pressed.connect(func():
		_equip_selected_item = null
		_show_equip_panel()
	)
	%EquipList.add_child(back_button)

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
	%EquipPanel.visible = false
	_refresh()

## README's CELL: "a selection of new pawns (pick one)". FloorFightRunner
## already builds the offer and applies a pick (swift, issue 5) -- this is
## the other half, asking the question and showing the result.
func _on_cell_room_entered(room: FloorRoom) -> void:
	var has_loss := false
	for pawn in party:
		if not run.is_alive(pawn.id):
			has_loss = true
			break
	if not has_loss:
		run.enter(room.id)
		_refresh("The cell is empty-handed: your party has nobody to replace.")
		return

	var candidates := FloorFightRunner.cell_candidates(run, room, party)
	if candidates.is_empty():
		run.enter(room.id)
		_refresh("The cell has nobody left to offer.")
		return

	_cell_room = room
	%CellPanel.visible = true
	_show_cell_panel(candidates)

func _show_cell_panel(candidates: Array[PawnData]) -> void:
	for child in %CellList.get_children():
		child.queue_free()

	var heading := Label.new()
	heading.text = "The cell offers a replacement:"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD
	heading.custom_minimum_size = Vector2(_EQUIP_PANEL_WIDTH - Palette.SPACE_L * 2.0, 0.0)
	%CellList.add_child(heading)

	for candidate in candidates:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
		var class_name_text := candidate.pawn_class.display_name if candidate.pawn_class != null else "?"
		button.text = "%s (%s)" % [candidate.display_name, class_name_text]
		button.pressed.connect(_on_cell_pawn_picked.bind(candidate))
		%CellList.add_child(button)

	var skip_button := Button.new()
	skip_button.text = "Leave empty-handed"
	skip_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	skip_button.pressed.connect(_on_cell_skipped)
	%CellList.add_child(skip_button)

func _on_cell_pawn_picked(chosen: PawnData) -> void:
	var room := _cell_room
	FloorFightRunner.resolve_cell(run, room, party, chosen)
	run.enter(room.id)
	_cell_room = null
	%CellPanel.visible = false
	_refresh("The cell grants you %s." % chosen.display_name)

func _on_cell_skipped() -> void:
	var room := _cell_room
	run.enter(room.id)
	_cell_room = null
	%CellPanel.visible = false
	_refresh()

func _slot_name(slot: EquipmentDef.Slot) -> String:
	match slot:
		EquipmentDef.Slot.WEAPON:
			return "weapon"
		EquipmentDef.Slot.ARMOR:
			return "armor"
		_:
			return "accessory"
