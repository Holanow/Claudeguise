extends "res://Tests/TestCase.gd"


## Issue 811: the loot loop, wired. `LootTables` and `FloorRun.add_loot` both
## existed and nothing had ever called either one.

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for id in [&"warrior", &"priest", &"geysermancer", &"siege_master"]:
		out.append(PawnFactory.make_starter_pawn(id, id, String(id)))
	return out


func test_a_room_holding_an_elite_is_a_big_enemy_room() -> void:
	assert_eq(FloorGenerator.ordinary_type_of(&"floor1_narrows_elite"), FloorRoom.Type.BIG_ENEMY)
	assert_eq(FloorGenerator.ordinary_type_of(&"floor1_sellsword"), FloorRoom.Type.BIG_ENEMY)


func test_every_other_ordinary_room_is_a_plain_enemy_room() -> void:
	for id in [&"floor1_room1", &"floor1_horde", &"floor1_ghoul_den", &"floor1_cover",
			&"floor1_hazard", &"floor1_chokepoint"]:
		assert_eq(FloorGenerator.ordinary_type_of(id), FloorRoom.Type.ENEMY,
			"%s holds no Elite and must not out-drop the room that does" % id)


func test_the_generator_places_those_types_on_the_floor() -> void:
	var plan := FloorGenerator.generate(7)
	var big := 0
	for room in plan.rooms:
		if room.type == FloorRoom.Type.BIG_ENEMY:
			big += 1
			assert_eq(FloorGenerator.ordinary_type_of(room.content_id), FloorRoom.Type.BIG_ENEMY)
	assert_eq(big, 2, "both elite rooms are placed on every floor")


func _room(type: FloorRoom.Type, content_id: StringName) -> FloorRoom:
	var r := FloorRoom.new()
	r.type = type
	r.content_id = content_id
	r.difficulty = 1
	return r


## A BOSS room drops at 1.0, so this is the award path with the roll removed.
func test_a_drop_lands_in_an_empty_slot_of_a_pawn_allowed_to_wear_it() -> void:
	var party := _party()
	var run := FloorRun.new()
	var item := FloorRun.award_room_loot(run, _room(FloorRoom.Type.BOSS, &"floor1_warden"), party, 3)
	assert_not_null(item, "a boss room always drops")
	assert_eq(run.loot.size(), 1)
	var wearer: PawnData = null
	for p in party:
		if p.get(FloorRun.SLOT_PROPERTY[item.slot]) == item:
			wearer = p
			break
	assert_not_null(wearer, "the drop reached a slot rather than only the loot list")
	assert_true(item.allows_class(wearer.pawn_class))


func test_nothing_ever_drops_into_a_slot_that_is_already_full() -> void:
	var party := _party()
	var run := FloorRun.new()
	var before := {}
	for p in party:
		before[p.id] = [p.main_hand, p.body]
	for i in 20:
		FloorRun.award_room_loot(run, _room(FloorRoom.Type.BOSS, &"room%d" % i), party, i)
	for p in party:
		assert_eq(p.main_hand, before[p.id][0], "a starting weapon is never replaced")
		assert_eq(p.body, before[p.id][1], "starting armour is never replaced")


func test_a_dead_pawn_picks_nothing_up() -> void:
	var party := _party()
	var run := FloorRun.new()
	for p in party:
		run.record_result(p.id, 0, 0, false)
	assert_eq(FloorRun.award_room_loot(run, _room(FloorRoom.Type.BOSS, &"floor1_warden"), party, 3), null,
		"a wiped party has nobody to hand an item to")
	assert_eq(run.loot.size(), 0)


func test_an_ordinary_enemy_room_pays_out_nothing() -> void:
	var party := _party()
	var run := FloorRun.new()
	for i in 30:
		FloorRun.award_room_loot(run, _room(FloorRoom.Type.ENEMY, &"room%d" % i), party, i)
	assert_eq(run.loot.size(), 0, "ENEMY is not in the drop table and this issue did not add it")


func test_the_same_floor_seed_pays_out_the_same_items() -> void:
	var a := FloorRun.new()
	var b := FloorRun.new()
	var party_a := _party()
	var party_b := _party()
	for i in 6:
		var room := _room(FloorRoom.Type.MINIBOSS, &"floor1_rat_king")
		FloorRun.award_room_loot(a, room, party_a, 11)
		FloorRun.award_room_loot(b, room, party_b, 11)
	assert_eq(a.loot.size(), b.loot.size())
	for i in a.loot.size():
		assert_eq(a.loot[i].id, b.loot[i].id, "the drop is a function of the floor seed")


func test_the_pickup_is_announced_in_the_next_room() -> void:
	var party := _party()
	var run := FloorRun.new()
	var item := FloorRun.award_room_loot(run, _room(FloorRoom.Type.BOSS, &"floor1_warden"), party, 3)
	assert_eq(run.pending_pickups.size(), 1)
	var state := CombatSim.build(party, RoomLibrary.get_room(&"floor1_room1"), 1)
	FloorRun.carry_into(run, state, party, 1)
	var said := 0
	for e in state.events:
		if e.kind == CG.EventKind.LOOT_AWARDED:
			said += 1
			assert_eq(e.item_id, item.id)
			assert_not_null(state.unit(e.target_id), "the event names the pawn that took it")
	assert_eq(said, 1, "the player is told exactly once")
	assert_eq(run.pending_pickups.size(), 0, "and not again in the room after that")


func test_the_drop_rate_multiplier_ships_at_one() -> void:
	assert_eq(LootTables.CHANCE_SCALE, 1.0)
