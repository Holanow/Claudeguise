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
	for item in batch:
		var equipped := false
		for p in party:
			if p.get(FloorRun.SLOT_PROPERTY[item.slot]) == item:
				equipped = true
		assert_true(equipped or run.bag.has(item), "every piece is worn or bagged, never lost")


## Issue 947 reverses the old rule that a full slot was never touched. What
## replaces it: strictly rarer wins, equal or worse leaves the incumbent alone.
func test_only_a_rarer_piece_displaces_what_is_already_worn() -> void:
	var party := _party()
	var run := FloorRun.new()
	var wearer := party[0]
	var incumbent: EquipmentDef = wearer.body
	assert_ne(incumbent, null, "the fixture needs a pawn who starts with a body piece")

	var sidegrade := incumbent.duplicate() as EquipmentDef
	sidegrade.id = &"test_sidegrade"
	FloorRun.take_chest(run, party, [sidegrade] as Array[EquipmentDef])
	assert_eq(wearer.body, incumbent, "an equal-rarity piece does not churn the slot")
	assert_true(run.bag.has(sidegrade), "and it goes to the bag instead")

	var upgrade := incumbent.duplicate() as EquipmentDef
	upgrade.id = &"test_upgrade"
	upgrade.affixes = [AffixRoll.new()] as Array[AffixRoll]
	assert_true(int(upgrade.rarity()) > int(incumbent.rarity()), "the fixture must be rarer")
	FloorRun.take_chest(run, party, [upgrade] as Array[EquipmentDef])
	assert_eq(wearer.body, upgrade, "a rarer piece takes the slot")
	assert_true(run.bag.has(incumbent), "and what it displaced goes to the bag")


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
## Issue 947: a full slot is no longer a closed slot, so a pity fixture has to
## out-rank every drop as well as fill every slot. Legendary is the affix cap.
static func _make_unbeatable(pawn: PawnData) -> void:
	for slot_property in FloorRun.SLOT_PROPERTY.values():
		var worn: EquipmentDef = pawn.get(slot_property)
		if worn == null:
			continue
		var capped := worn.duplicate() as EquipmentDef
		var rolls: Array[AffixRoll] = []
		for _i in int(EquipmentDef.Rarity.LEGENDARY):
			rolls.append(AffixRoll.new())
		capped.affixes = rolls
		pawn.set(slot_property, capped)


func test_the_pity_counter_forces_a_wearable_piece() -> void:
	var party := _party()
	var run := FloorRun.new()
	for p in party:
		p.head = ItemLibrary.get_equipment(&"great_helm") \
			if p.pawn_class.method == CG.Method.MARTIAL else ItemLibrary.get_equipment(&"hood")
		p.accessory = ItemLibrary.get_equipment(&"censer")
		_make_unbeatable(p)
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


## Issue 938: and the roll reads that number, not the room's. The gate opening
## on a difficulty-2 room on floor 1 is the exact failure #916 named.
func _verbs_in_chests(floor_index: int, difficulty: int) -> int:
	var room := _room(FloorRoom.Type.ENEMY, &"floor1_room1")
	room.difficulty = difficulty
	var verbs := 0
	for s in 60:
		var run := FloorRun.new()
		run.floor_index = floor_index
		for item in FloorRun.roll_room_loot(run, room, _party(), s):
			for r in item.affixes:
				if r != null and r.affix != null and r.affix.kind == AffixDef.Kind.VERB:
					verbs += 1
	return verbs

func test_a_hard_room_on_floor_one_still_rolls_no_verb() -> void:
	assert_eq(_verbs_in_chests(1, 9), 0,
		"room difficulty opened the verb tier, which is what #916 forbade")

func test_an_easy_room_on_the_unlock_floor_can_roll_a_verb() -> void:
	assert_true(_verbs_in_chests(ItemRoller.VERB_UNLOCK_FLOOR, 1) > 0,
		"the run's own floor number never reached the roller")


## Issue 950: rarity still decides first, and a tie on rarity is broken by
## weighted total stats rather than left alone.
func test_a_rarity_tie_is_broken_by_total_stats() -> void:
	var party := _party()
	var run := FloorRun.new()
	var wearer := party[0]
	var incumbent: EquipmentDef = wearer.body

	var richer := incumbent.duplicate() as EquipmentDef
	richer.id = &"test_richer"
	richer.attribute_flat = {CG.Attribute.STR: 3}
	assert_eq(int(richer.rarity()), int(incumbent.rarity()), "the fixture must tie on rarity")
	assert_true(FloorRun.stat_score(richer) > FloorRun.stat_score(incumbent))
	FloorRun.take_chest(run, party, [richer] as Array[EquipmentDef])
	assert_eq(wearer.body, richer, "the richer of two equally rare pieces takes the slot")
	assert_true(run.bag.has(incumbent), "and what it displaced goes to the bag")


## The negative: equal rarity and equal stats still leaves the incumbent alone.
func test_an_equal_piece_still_does_not_churn_the_slot() -> void:
	var party := _party()
	var run := FloorRun.new()
	var wearer := party[0]
	var incumbent: EquipmentDef = wearer.body

	var equal := incumbent.duplicate() as EquipmentDef
	equal.id = &"test_equal"
	assert_eq(FloorRun.stat_score(equal), FloorRun.stat_score(incumbent))
	FloorRun.take_chest(run, party, [equal] as Array[EquipmentDef])
	assert_eq(wearer.body, incumbent, "an equal piece does not churn the slot")
	assert_true(run.bag.has(equal), "and it goes to the bag instead")


## A poorer piece of the same rarity is refused, which is what stops the
## tiebreaker from becoming a coin flip.
func test_a_poorer_piece_of_the_same_rarity_is_refused() -> void:
	var party := _party()
	var run := FloorRun.new()
	var wearer := party[0]
	var incumbent: EquipmentDef = wearer.body

	var poorer := incumbent.duplicate() as EquipmentDef
	poorer.id = &"test_poorer"
	poorer.damage_reduction = incumbent.damage_reduction * 0.5
	assert_true(FloorRun.stat_score(poorer) < FloorRun.stat_score(incumbent))
	FloorRun.take_chest(run, party, [poorer] as Array[EquipmentDef])
	assert_eq(wearer.body, incumbent, "a poorer piece of the same rarity is refused")


## Issue 950: two-handers join the upgrade path. One displaces both hands and
## both displaced pieces go to the bag.
func test_a_two_hander_displaces_both_hands_into_the_bag() -> void:
	var party: Array[PawnData] = [
		PawnFactory.make_starter_pawn(&"geysermancer", &"geysermancer", "geysermancer")]
	var run := FloorRun.new()
	var wearer := party[0]
	var main: EquipmentDef = wearer.main_hand
	var off: EquipmentDef = wearer.off_hand
	assert_ne(main, null, "the fixture needs a filled main hand")
	assert_ne(off, null, "the fixture needs a filled off hand")

	var staff := ItemLibrary.get_equipment(&"staff").duplicate() as EquipmentDef
	staff.affixes = [AffixRoll.new()] as Array[AffixRoll]
	assert_true(staff.two_handed, "the fixture must be two-handed")
	FloorRun.take_chest(run, party, [staff] as Array[EquipmentDef])
	assert_eq(wearer.main_hand, staff, "a rarer two-hander takes the main hand")
	assert_eq(wearer.off_hand, null, "and it occupies the off hand, so nothing is worn there")
	assert_true(run.bag.has(main), "the displaced main hand goes to the bag")
	assert_true(run.bag.has(off), "and so does the off hand it cost")


## The two-hander is scored against the main hand alone, not against the pair:
## a main hand it cannot beat refuses it however poor the off hand is.
func test_a_two_hander_is_compared_against_the_main_hand_only() -> void:
	var party: Array[PawnData] = [
		PawnFactory.make_starter_pawn(&"geysermancer", &"geysermancer", "geysermancer")]
	var run := FloorRun.new()
	var wearer := party[0]
	var main: EquipmentDef = wearer.main_hand
	var off: EquipmentDef = wearer.off_hand
	wearer.main_hand = main.duplicate() as EquipmentDef
	wearer.main_hand.affixes = [AffixRoll.new(), AffixRoll.new()] as Array[AffixRoll]

	var staff := ItemLibrary.get_equipment(&"staff").duplicate() as EquipmentDef
	staff.affixes = [AffixRoll.new()] as Array[AffixRoll]
	FloorRun.take_chest(run, party, [staff] as Array[EquipmentDef])
	assert_true(run.bag.has(staff), "a two-hander that loses to the main hand is bagged")
	assert_eq(wearer.off_hand, off, "and the off hand it never took is untouched")
