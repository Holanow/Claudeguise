extends "res://Tests/TestCase.gd"


## Issue 805: the floor's picker, drawn in the room. A resolved room opens a
## door on every edge it can be left through, a click on one walks the party
## into that room, and nothing advances a floor except that click.

const BattleScene := preload("res://Scenes/Battle.tscn")
const FLOOR_SEED := 3

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		out.append(PawnFactory.make_preset_pawn(cid, cid, String(cid)))
	return out

## A battle standing in the entrance of a real floor, its first fight built and
## held. Nothing here runs a fight: every test below resolves it by hand.
func _floor() -> Node:
	var battle := in_tree(BattleScene.instantiate())
	var cfg := RunConfig.new()
	cfg.seed = FLOOR_SEED
	cfg.party = _party()
	battle.begin_floor(cfg, FloorGenerator.generate(FLOOR_SEED))
	return battle

func _resolve(battle: Node) -> void:
	battle.state.outcome = CombatState.Outcome.PLAYER_WIN
	battle._handle_fight_end()

# ---------------------------------------------------------------------------
# where a door is

func test_each_door_sits_on_the_edge_it_leaves_through() -> void:
	var half := Vector2(CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_HEIGHT)
	for dir in FloorPlan.DIRECTIONS:
		var rect := FloorDoors.rect_for(dir)
		var centre := rect.get_center()
		assert_almost_eq(centre.x, float(dir.x) * (half.x - FloorDoors.DOOR_SIZE * 0.5), 0.01,
			"%s door x" % FloorPlan.direction_name(dir))
		assert_almost_eq(centre.y, float(dir.y) * (half.y - FloorDoors.DOOR_SIZE * 0.5), 0.01,
			"%s door y" % FloorPlan.direction_name(dir))
		assert_true(absf(centre.x) + FloorDoors.DOOR_SIZE * 0.5 <= half.x + 0.01,
			"a door must not hang outside the arena")
		assert_true(absf(centre.y) + FloorDoors.DOOR_SIZE * 0.5 <= half.y + 0.01,
			"a door must not hang outside the arena")

func test_a_door_nobody_has_opened_is_not_clickable() -> void:
	var doors := FloorDoors.new()
	assert_eq(doors.room_at(FloorDoors.rect_for(Vector2i(0, -1)).get_center()), -1,
		"a hidden door takes no clicks")
	doors.show_exits([{"room_id": 7, "dir": Vector2i(0, -1)}])
	assert_eq(doors.room_at(FloorDoors.rect_for(Vector2i(0, -1)).get_center()), 7)
	assert_eq(doors.room_at(Vector2.ZERO), -1, "the middle of the room is not a door")
	doors.clear_exits()
	assert_eq(doors.room_at(FloorDoors.rect_for(Vector2i(0, -1)).get_center()), -1)
	doors.free()

# ---------------------------------------------------------------------------
# when a door is open

## "An open door mid-fight is a lie about what the player can do."
func test_the_doors_are_shut_while_the_fight_is_unresolved() -> void:
	var battle := _floor()
	assert_false(battle.doors_open(), "a room that is still a fight has no doors")
	assert_true(battle.open_exits().is_empty())
	for dir in FloorPlan.DIRECTIONS:
		assert_eq(battle.door_room_at(FloorDoors.rect_for(dir).get_center()), -1,
			"no click lands on a %s door mid-fight" % FloorPlan.direction_name(dir))

func test_a_resolved_room_opens_one_door_per_neighbour() -> void:
	var battle := _floor()
	var walk: FloorWalk = battle._floor_walk
	var expected := walk.plan.exits_of(walk.current_id)
	_resolve(battle)
	assert_true(battle.doors_open(), "a resolved room opens its doors")
	assert_eq(battle.open_exits().size(), expected.size(),
		"one door per neighbour, and no others")
	assert_true(expected.size() > 0, "the entrance must have somewhere to go")
	for e in expected:
		assert_eq(battle.door_room_at(FloorDoors.rect_for(e["dir"]).get_center()),
			int(e["room_id"]), "the %s door walks into its own neighbour" % FloorPlan.direction_name(e["dir"]))

## The fight-end path runs every frame until something takes a door, so the
## room's payout has to fire once rather than once a frame.
func test_a_room_pays_out_once_however_long_its_doors_stand_open() -> void:
	var battle := _floor()
	_resolve(battle)
	var loot: int = battle._floor_run.loot.size()
	var cleared: int = battle._floor_walk.cleared_count()
	for i in 5:
		battle._handle_fight_end()
	assert_eq(battle._floor_run.loot.size(), loot, "the drop table pays out once")
	assert_eq(battle._floor_walk.cleared_count(), cleared)

# ---------------------------------------------------------------------------
# what a click does

func test_clicking_a_door_walks_into_that_room_and_slides_there() -> void:
	var battle := _floor()
	var walk: FloorWalk = battle._floor_walk
	var from := walk.current_id
	_resolve(battle)
	var exit: Dictionary = battle.open_exits()[0]
	var room_id := int(exit["room_id"])
	battle.take_door(room_id)
	assert_false(battle.doors_open(), "the doors shut behind the party")
	assert_ne(from, room_id, "the fixture must walk somewhere else")
	assert_eq(walk.current_id, room_id, "the room the player clicked is the room that arrives")
	assert_ne(battle._slide_offset, Vector2.ZERO,
		"the arriving room starts off the screen and travels onto it")
	battle._advance_slide(BattleView.FLOOR_SLIDE_SECONDS * 0.5)
	assert_ne(battle._slide_offset, Vector2.ZERO, "the screen travels rather than cutting")
	battle._advance_slide(BattleView.FLOOR_SLIDE_SECONDS)
	assert_eq(walk.current_id, room_id, "the party arrives in the room they clicked")
	assert_eq(battle._slide_offset, Vector2.ZERO, "the arena lands back on its layout")

func test_nothing_advances_a_floor_but_a_door() -> void:
	var battle := _floor()
	var walk: FloorWalk = battle._floor_walk
	var from := walk.current_id
	_resolve(battle)
	var neighbours := walk.plan.neighbours_of(from)
	for id in walk.plan.rooms.size():
		if not neighbours.has(id):
			battle.take_door(id)
	assert_eq(walk.current_id, from, "a room with no door onto it cannot be walked into")
	assert_true(battle.doors_open(), "and the doors are still standing open")

# ---------------------------------------------------------------------------
# walking back through a cleared room

func test_a_cleared_room_is_walked_back_through_rather_than_fought_again() -> void:
	var room := RoomLibrary.get_room(&"floor1_room1")
	assert_true(room.enemy_spawns.size() > 0, "the fixture room must have enemies")
	var empty := BattleView._emptied(room)
	assert_eq(empty.enemy_spawns.size(), 0, "a cleared room holds nobody to fight")
	assert_eq(empty.id, room.id)
	assert_eq(empty.party_spawns, room.party_spawns, "the party still stands where it stood")
	assert_eq(room.enemy_spawns.size() > 0, true, "and the library's own copy is untouched")

## Without this the party paces between two cleared rooms and heals for free.
func test_walking_back_into_a_cleared_room_does_not_heal() -> void:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w", "W")]
	var state := CombatSim.build(party, RoomLibrary.get_room(&"floor1_room1"), 1)
	var run := FloorRun.new()
	run.record_result(&"w", 1, 0, true)
	FloorRun.carry_into(run, state, party, 0, null, false)
	assert_eq(state.unit(0).hp, 1, "the carried hp, and nothing on top of it")

func test_the_arrival_heal_is_still_the_default() -> void:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w", "W")]
	var state := CombatSim.build(party, RoomLibrary.get_room(&"floor1_room1"), 1)
	var run := FloorRun.new()
	run.record_result(&"w", 1, 0, true)
	FloorRun.carry_into(run, state, party)
	assert_true(state.unit(0).hp > 1, "a first arrival heals as it always did")

# ---------------------------------------------------------------------------
# the camp, reached by choice

## Issue 803's camp is a room on the graph, so it is behind a door like every
## other room. This is what makes it something the player can decide to walk to.
func test_the_camp_is_behind_a_door_the_player_can_click() -> void:
	for seed in range(20):
		var plan := FloorGenerator.generate(seed)
		if plan.camp_id < 0:
			continue
		var walk := FloorWalk.new(plan)
		var route := walk.route_to_camp()
		assert_true(not route.is_empty(), "seed %d: the camp must be walkable to" % seed)
		for id in route:
			if id == plan.camp_id:
				break
			walk.enter(id)
		var reachable := false
		for e in walk.exits():
			if int(e["room_id"]) == plan.camp_id:
				reachable = true
		assert_true(reachable, "seed %d: the last step to the camp is a door" % seed)
