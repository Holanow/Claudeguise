extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")
const MainScript := preload("res://Scripts/UI/Main.gd")

## Issue 591: "The fight end screen should let me pick another level." The
## rooms come from `RoomLibrary.pickable_ids()`, the same list party
## select offers, so #587's conversion of rooms to scenes has one place to
## change rather than two.

func _spawn(encounter_id: StringName = &"") -> Node2D:
	## `_ready()` is NOT called by hand here. `in_tree` puts the node in the
	## tree and the engine fires it; calling it again builds the end banner a
	## second time, and the first one -- the one a walk of the tree finds --
	## then belongs to no live dictionary. That cost twenty minutes.
	var view = in_tree(BattleScene.instantiate())
	if encounter_id != &"":
		var cfg := RunConfig.new()
		cfg.encounter_id = encounter_id
		view.config = cfg
	return view

func _resolved(view) -> void:
	var state := CombatState.new(0)
	state.tick = 90
	state.outcome = CombatState.Outcome.PLAYER_WIN
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.hp = 10
	u.hp_max = 10
	u.display_name = "Warrior"
	state.units.append(u)
	view.state = state
	view._show_outcome()

func _picker(view) -> Node:
	return _find(view, BattleView.ROOM_PICKER_NAME)

func _find(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find(child, wanted)
		if found != null:
			return found
	return null

func _room_buttons(view) -> Array:
	var out := []
	var picker := _picker(view)
	if picker == null:
		return out
	for n in _walk(picker):
		if n is Button:
			out.append(n)
	return out

func _walk(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

## Every room party select offers is offered here too. Asserted against the
## registry rather than against a list typed into this file, which would be two
## artifacts by one author and could be wrong in the same place twice.
func test_the_end_card_offers_every_pickable_room() -> void:
	var view = _spawn()
	_resolved(view)
	var buttons := _room_buttons(view)
	var wanted := RoomLibrary.pickable_ids()
	assert_true(wanted.size() > 0, "no room is pickable at all, so this proves nothing")
	assert_eq(buttons.size(), wanted.size(), "one button per pickable room")
	for id in wanted:
		var room = RoomLibrary.get_room(id)
		var text := BattleView.room_button_text(id, room)
		var found := false
		for b in buttons:
			if b.text == text:
				found = true
		assert_true(found, "'%s' is pickable and not offered on the end card" % id)
	view.free()

## Pressing one asks for that room by id. The id, not an index: #587 is moving
## rooms into scenes and an index would not survive the move.
func test_pressing_a_room_asks_for_that_room_by_id() -> void:
	var wanted := RoomLibrary.pickable_ids()
	var target: StringName = wanted[wanted.size() - 1]
	var view = _spawn()
	_resolved(view)
	var asked: Array[StringName] = []
	view.room_requested.connect(func(id: StringName): asked.append(id))
	var room = RoomLibrary.get_room(target)
	for b in _room_buttons(view):
		if b.text == BattleView.room_button_text(target, room):
			b.pressed.emit()
	assert_eq(asked, [target] as Array[StringName], "the wrong room, or none, was asked for")
	view.free()

## The room the player is already in is shown and dead. A list that changes
## length between fights is a list you have to re-read.
func test_the_room_you_are_in_is_shown_and_dead() -> void:
	var here: StringName = RoomLibrary.pickable_ids()[0]
	var view = _spawn(here)
	_resolved(view)
	var room = RoomLibrary.get_room(here)
	var text := BattleView.room_button_text(here, room)
	var disabled := 0
	for b in _room_buttons(view):
		if b.disabled:
			disabled += 1
			assert_eq(b.text, text, "a room that is not the current one is dead")
	assert_eq(disabled, 1, "exactly the current room is dead")
	view.free()

## The floor is not a choice on this card, so the name drops it. A room whose
## name carries no comma keeps the whole name rather than losing its front.
func test_the_button_names_the_room_without_the_floor() -> void:
	var room := RoomData.new()
	room.display_name = "Floor 1, The Narrows"
	assert_eq(BattleView.room_button_text(&"x", room), "The Narrows")
	var plain := RoomData.new()
	plain.display_name = "The Narrows"
	assert_eq(BattleView.room_button_text(&"x", plain), "The Narrows")
	var unnamed := RoomData.new()
	assert_eq(BattleView.room_button_text(&"floor1_room1", unnamed), "floor1_room1",
		"a room with no display name must still be pressable")

## Each button says what the room holds, off the `Encounter` itself through the
## same `room_summary` party select prints. A blurb written beside it would go
## quietly false the day somebody moves a pillar.
func test_each_room_button_says_what_is_in_the_room() -> void:
	var view = _spawn()
	_resolved(view)
	for b in _room_buttons(view):
		assert_true(b.tooltip_text.length() > 0, "'%s' says nothing about its room" % b.text)
		assert_true(b.has_method("_make_custom_tooltip"),
			"'%s' falls back to the engine's grey tooltip" % b.text)
	view.free()

## And the other end of the wire: `Main` turns the ask into the same party and
## the same seed in the room that was asked for.
func test_main_keeps_the_party_and_the_seed_and_changes_only_the_room() -> void:
	var main := in_tree(Node.new())
	main.set_script(MainScript)
	var cfg := RunConfig.new()
	cfg.seed = 0xBEEF
	cfg.encounter_id = &"floor1_room1"
	cfg.party = [PawnFactory.make_starter_pawn(&"warrior", &"p0", "P0")] as Array[PawnData]
	main.run_config = cfg
	main.fight_room(&"floor1_chokepoint")
	assert_eq(main.run_config.encounter_id, &"floor1_chokepoint", "the room did not change")
	assert_eq(main.run_config.seed, 0xBEEF, "the seed changed, so it is not the same fight")
	assert_eq(main.run_config.party, cfg.party, "the party was rebuilt, losing its plans and gear")
	main.free()

## The placement is deliberately dropped: it was chosen against the old room's
## terrain and a pawn deployed into a wall is worse than the room's own spawns.
func test_the_old_rooms_placement_is_not_carried_into_the_new_room() -> void:
	var main := in_tree(Node.new())
	main.set_script(MainScript)
	var cfg := RunConfig.new()
	cfg.encounter_id = &"floor1_room1"
	cfg.party = [PawnFactory.make_starter_pawn(&"warrior", &"p0", "P0")] as Array[PawnData]
	main.run_config = cfg
	main._party_positions = [Vector2(-100.0, 40.0)] as Array[Vector2]
	main.fight_room(&"floor1_chokepoint")
	assert_true(main._party_positions.is_empty(),
		"the old room's placement followed the party into a room it was never measured in")
	main.free()
