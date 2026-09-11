extends "res://Tests/TestCase.gd"


## Issue 917: a two-handed weapon occupies the off hand as well, so its wielder
## gives up whatever action an off hand would have granted.


func _staff() -> EquipmentDef:
	return ItemLibrary.get_equipment(&"staff")


## The shipped two-hander. Only the Staff carries the flag today, because the
## Reaper the README pairs it with does not exist yet.
func test_the_staff_is_the_two_handed_weapon_that_ships() -> void:
	var two_handed: Array[StringName] = []
	for id in ItemLibrary.all_ids():
		if ItemLibrary.get_equipment(id).two_handed:
			two_handed.append(id)
	assert_eq(two_handed, [&"staff"] as Array[StringName])


## The occupancy itself, read through the one call every caller uses.
func test_a_two_handed_main_hand_blocks_the_off_hand() -> void:
	var pawn := PawnData.new()
	pawn.main_hand = _staff()
	assert_true(pawn.off_hand_blocked(), "a staff should occupy the off hand")
	pawn.main_hand = ItemLibrary.get_equipment(&"sword")
	assert_false(pawn.off_hand_blocked(), "a sword should leave the off hand free")
	pawn.main_hand = null
	assert_false(pawn.off_hand_blocked(), "an empty main hand blocks nothing")


## The cost the issue says is load-bearing: the off hand's granted action goes
## away. Read through `ActionLibrary`, which is what the plan editor reads, on
## a classless pawn so the only source of an action is the gear.
func test_a_two_hander_gives_up_the_off_hand_action() -> void:
	var pawn := PawnData.new()
	pawn.main_hand = ItemLibrary.get_equipment(&"sword")
	pawn.off_hand = ItemLibrary.get_equipment(&"focus")
	assert_true(ActionLibrary.actions_for_pawn(pawn).has(&"channel_mana"),
		"the Focus should grant Channel Mana to a one-handed wielder")

	pawn.main_hand = _staff()
	assert_false(ActionLibrary.actions_for_pawn(pawn).has(&"channel_mana"),
		"a staff occupies the off hand, so the Focus must grant nothing")
	assert_false(pawn.equipment().has(pawn.off_hand),
		"a blocked off hand must not reach the simulation at all")


## An off hand a pawn cannot use must never be filled, or the starting loadout
## claims an action the fight does not give it.
func test_no_starter_pawn_carries_a_blocked_off_hand() -> void:
	var was := PawnFactory.FILL_EMPTY_SLOTS
	PawnFactory.FILL_EMPTY_SLOTS = true
	for class_id in ClassLibrary.all_ids():
		var pawn := PawnFactory.make_starter_pawn(class_id, class_id, "x")
		if pawn.off_hand_blocked():
			assert_eq(pawn.off_hand, null,
				"%s holds a two-hander and an off hand at once" % class_id)
		else:
			assert_true(pawn.off_hand != null, "%s got no off hand" % class_id)
	PawnFactory.FILL_EMPTY_SLOTS = was


## The Priest is the class the flag moves: staff plus focus becomes staff
## alone, which is the whole trade #917 describes.
func test_the_priest_starts_with_a_staff_and_no_off_hand() -> void:
	var priest := PawnFactory.make_starter_pawn(&"priest", &"p", "p")
	assert_eq(priest.main_hand.id, &"staff")
	assert_eq(priest.off_hand, null, "the Staff is two-handed, so the Focus cannot be worn with it")


## The drop filter, which #833 showed is where a wrong answer hides: an off
## hand must not be offered to a pawn that cannot put one on.
func test_a_drop_never_lands_an_off_hand_on_a_two_hander() -> void:
	var priest := PawnFactory.make_starter_pawn(&"priest", &"priest", "P")
	var run := FloorRun.new()
	assert_eq(FloorRun._taker_for(run, [priest] as Array[PawnData], ItemLibrary.get_equipment(&"focus")), null,
		"the Priest holds a staff and must not be given a Focus")

	priest.main_hand = ItemLibrary.get_equipment(&"orb")
	assert_eq(FloorRun._taker_for(run, [priest] as Array[PawnData], ItemLibrary.get_equipment(&"focus")), priest,
		"with a one-handed main hand the same Focus must land")


## And the other direction: a two-hander must not land on a pawn whose off hand
## is already full, because equipping it would silently disable that piece.
func test_a_two_hander_never_lands_on_a_pawn_wearing_an_off_hand() -> void:
	var geysermancer := PawnFactory.make_starter_pawn(&"geysermancer", &"g", "G")
	geysermancer.main_hand = null
	var run := FloorRun.new()
	assert_eq(FloorRun._taker_for(run, [geysermancer] as Array[PawnData], _staff()), null,
		"the Focus is worn, so a Staff has nowhere to go")

	geysermancer.off_hand = null
	assert_eq(FloorRun._taker_for(run, [geysermancer] as Array[PawnData], _staff()), geysermancer,
		"with both hands free the Staff must land")
