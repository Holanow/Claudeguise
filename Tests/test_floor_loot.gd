extends "res://Tests/TestCase.gd"


## Issue 919: the chest a cleared room leaves behind, rolled when the room
## resolves and emptied when the player clicks it. Issue 811 built the loop and
## #833 measured it delivering one item type across 40 runs; the acceptance here
## is `Tools/ChestSweep.gd`'s distribution, and these are its guards.

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
			"%s holds no Elite and its type must still be derived from its content" % id)


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


## The player's rate: every fight pays out, including the plain ENEMY room that
## used to pay nothing.
func test_an_ordinary_enemy_room_fills_a_chest() -> void:
	var party := _party()
	var run := FloorRun.new()
	var batch := FloorRun.roll_room_loot(run, _room(FloorRoom.Type.ENEMY, &"floor1_room1"), party, 3)
	assert_true(batch.size() >= 1, "an ordinary fight pays out on floor 1")


func test_the_camp_fills_no_chest() -> void:
	var party := _party()
	var run := FloorRun.new()
	assert_eq(FloorRun.roll_room_loot(run, _room(FloorRoom.Type.CAMP, &"camp"), party, 3),
		[] as Array[EquipmentDef], "the camp is not a fight")


## Rolling fills the chest and hands nothing over; only the click does.
func test_rolling_the_chest_gives_the_party_nothing() -> void:
	var party := _party()
	var run := FloorRun.new()
	var before := {}
	for p in party:
		before[p.id] = p.head
	FloorRun.roll_room_loot(run, _room(FloorRoom.Type.BOSS, &"floor1_warden"), party, 3)
	assert_eq(run.loot.size(), 0, "the chest is not the party's until it is clicked")
	for p in party:
		assert_eq(p.head, before[p.id], "a chest nobody opened dressed somebody")


func test_opening_the_chest_records_everything_and_wears_what_fits() -> void:
	var party := _party()
	var run := FloorRun.new()
	var batch := FloorRun.roll_room_loot(run, _room(FloorRoom.Type.BOSS, &"floor1_warden"), party, 3)
	var worn := FloorRun.take_chest(run, party, batch)
	assert_eq(run.loot.size(), batch.size(), "every piece is recorded, worn or not")
	assert_eq(run.bag.size(), batch.size() - worn, "what nobody could wear is in the bag")


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
	assert_eq(FloorRun.award_room_loot(run, _room(FloorRoom.Type.BOSS, &"floor1_warden"), party, 3),
		[] as Array[EquipmentDef], "a wiped party has nobody to fill a chest for")
	assert_eq(run.loot.size(), 0)


func test_the_same_floor_seed_pays_out_the_same_items() -> void:
	var a := FloorRun.new()
	var b := FloorRun.new()
	var party_a := _party()
	var party_b := _party()
	for i in 6:
		var room := _room(FloorRoom.Type.MINIBOSS, &"room%d" % i)
		FloorRun.award_room_loot(a, room, party_a, 11)
		FloorRun.award_room_loot(b, room, party_b, 11)
	assert_true(a.loot.size() > 0, "six chests must pay out something")
	assert_eq(a.loot.size(), b.loot.size())
	for i in a.loot.size():
		assert_eq(a.loot[i].display_name, b.loot[i].display_name,
			"the chest is a function of the floor seed")


## The pity counter. A party with nothing empty wears nothing, and after
## PITY_LIMIT such chests the next one must carry something that fits.
func test_the_pity_counter_forces_a_wearable_piece() -> void:
	var party := _party()
	var run := FloorRun.new()
	for p in party:
		p.head = ItemLibrary.get_equipment(&"great_helm") \
			if p.pawn_class.method == CG.Method.MARTIAL else ItemLibrary.get_equipment(&"hood")
		p.accessory = ItemLibrary.get_equipment(&"censer")
	for i in LootTables.PITY_LIMIT:
		FloorRun.award_room_loot(run, _room(FloorRoom.Type.ENEMY, &"room%d" % i), party, i)
	assert_eq(run.unworn_chests, LootTables.PITY_LIMIT,
		"a party with no empty slot should have worn nothing")

	## Now free one slot and the very next chest has to fill it.
	party[0].accessory = null
	FloorRun.award_room_loot(run, _room(FloorRoom.Type.ENEMY, &"pity"), party, 99)
	assert_eq(run.unworn_chests, 0, "the pity chest dressed nobody")


## And the counter resets the moment a chest does dress somebody, so an ordinary
## run never reaches the floor.
func test_a_chest_that_dresses_somebody_resets_the_counter() -> void:
	var party := _party()
	var run := FloorRun.new()
	run.unworn_chests = 2
	FloorRun.take_chest(run, party, [ItemLibrary.get_equipment(&"censer")] as Array[EquipmentDef])
	assert_eq(run.unworn_chests, 0)


func test_the_pickup_is_announced_in_the_next_room() -> void:
	var party := _party()
	var run := FloorRun.new()
	## Chests until one dresses somebody: what drops is weighted, so a single
	## chest landing on nobody is an ordinary outcome rather than a defect.
	for i in 12:
		FloorRun.award_room_loot(run, _room(FloorRoom.Type.BOSS, &"room%d" % i), party, i)
		if not run.pending_pickups.is_empty():
			break
	var expected := run.pending_pickups.size()
	assert_true(expected > 0, "twelve chests dressed nobody at all")
	var state := CombatSim.build(party, RoomLibrary.get_room(&"floor1_room1"), 1)
	FloorRun.carry_into(run, state, party, 1)
	var said := 0
	for e in state.events:
		if e.kind == CG.EventKind.LOOT_AWARDED:
			said += 1
			assert_not_null(state.unit(e.target_id), "the event names the pawn that took it")
	assert_eq(said, expected, "the player is told once per piece worn")
	assert_eq(run.pending_pickups.size(), 0, "and not again in the room after that")


## Issue 916: the floor number is the floor's, never the room's difficulty.
func test_a_run_carries_a_floor_number_of_its_own() -> void:
	var run := FloorRun.new()
	assert_eq(run.floor_index, 1, "a run starts on floor 1")
