extends "res://Tests/TestCase.gd"


## Issue 131's stopgap: a generated pawn's attributes are rolled from the seed.
## The player's ruling drew one line through it -- *"I wouldn't randomise WIS
## access, give it a baseline and let gear improve it"* -- and most of what is
## asserted here defends that line and the fixed roster beside it.


## The whole reason a fixed roster has to exist. Every measurement in this
## repo compares arms built from `make_starter_pawn`, so it must never roll.
func test_the_fixed_roster_is_the_default_and_never_moves() -> void:
	for class_id in Registry.all_class_ids():
		var a := PawnFactory.make_starter_pawn(class_id, &"p", "p")
		var b := PawnFactory.make_starter_pawn(class_id, &"p", "p")
		assert_true(a.attribute_bonus.is_empty(), "%s starter pawn carries a roll" % class_id)
		for attr in _all_attributes():
			assert_eq(a.attribute(attr), b.attribute(attr),
				"%s starter pawn is not reproducible on %s" % [class_id, CG.attribute_name(attr)])
			assert_eq(a.attribute(attr), Registry.get_class_def(class_id).attribute(attr),
				"%s starter pawn differs from its class spread" % class_id)


## The ruling, asserted where it can be broken rather than only written down.
func test_wis_is_never_rolled_and_stays_at_its_class_baseline() -> void:
	assert_false(PawnFactory.ROLLED_ATTRIBUTES.has(CG.Attribute.WIS),
		"WIS is in the rolled set and the player ruled it out")
	for class_id in Registry.all_class_ids():
		var baseline := Registry.get_class_def(class_id).attribute(CG.Attribute.WIS)
		for s in 40:
			var pawn := PawnFactory.make_rolled_pawn(class_id, &"p", "p", s)
			assert_eq(pawn.attribute(CG.Attribute.WIS), baseline,
				"%s rolled WIS on seed %d" % [class_id, s])


## The reason the baseline is per class and not one shared number: a generated
## pawn must always be able to run its own class library.
func test_every_rolled_pawn_can_still_run_its_whole_class_library() -> void:
	for class_id in Registry.all_class_ids():
		for s in 40:
			var pawn := PawnFactory.make_rolled_pawn(class_id, &"p", "p", s)
			pawn.plans = PresetPlans.for_class(class_id)
			assert_true(Balance.plan_block_budget(pawn) >= PresetPlans.total_blocks(class_id),
				"%s on seed %d cannot run its own library" % [class_id, s])


## Rolled from the seed, never from a fresh generator, or nothing can be
## reproduced and every tool's arms stop comparing.
func test_the_same_seed_rolls_the_same_pawn_and_a_different_seed_does_not() -> void:
	for class_id in Registry.all_class_ids():
		var a := PawnFactory.make_rolled_pawn(class_id, &"p", "p", 12345)
		var b := PawnFactory.make_rolled_pawn(class_id, &"p", "p", 12345)
		assert_eq(a.attribute_bonus, b.attribute_bonus, "%s is not reproducible" % class_id)
	var moved := 0
	for class_id in Registry.all_class_ids():
		var a := PawnFactory.make_rolled_pawn(class_id, &"p", "p", 1)
		var b := PawnFactory.make_rolled_pawn(class_id, &"p", "p", 2)
		if a.attribute_bonus != b.attribute_bonus:
			moved += 1
	assert_eq(moved, Registry.all_class_ids().size(), "a different seed rolled the same pawns")


## One generator per class. A shared stream would make each pawn's roll depend
## on how many classes were built before it, so a sixth class would silently
## reroll the other five.
func test_a_class_roll_does_not_depend_on_the_other_classes() -> void:
	var alone := PawnFactory.make_rolled_pawn(&"warrior", &"p", "p", 777)
	for other in [&"priest", &"geysermancer", &"siege_master", &"abomination"]:
		PawnFactory.make_rolled_pawn(other, &"p", "p", 777)
	var after := PawnFactory.make_rolled_pawn(&"warrior", &"p", "p", 777)
	assert_eq(alone.attribute_bonus, after.attribute_bonus,
		"the Warrior's roll moved when other classes were built around it")


## The spread is what it says, and the floor holds. A class value of 1 must not
## become 0 and silently switch off whatever reads it.
func test_a_roll_stays_inside_its_spread_and_never_falls_below_the_floor() -> void:
	var seen_low := false
	var seen_high := false
	var under_floor := []
	var over_spread := []
	for class_id in Registry.all_class_ids():
		var cls := Registry.get_class_def(class_id)
		for s in 200:
			var pawn := PawnFactory.make_rolled_pawn(class_id, &"p", "p", s)
			for a in PawnFactory.ROLLED_ATTRIBUTES:
				var base := cls.attribute(a)
				var value := pawn.attribute(a)
				if value < PawnFactory.ROLL_FLOOR:
					under_floor.append("%s %s=%d seed %d" % [class_id, CG.attribute_name(a), value, s])
				if value > base + PawnFactory.ROLL_SPREAD:
					over_spread.append("%s %s=%d base %d seed %d" % [class_id, CG.attribute_name(a), value, base, s])
				seen_low = seen_low or value == base - PawnFactory.ROLL_SPREAD
				seen_high = seen_high or value == base + PawnFactory.ROLL_SPREAD
	assert_eq(under_floor, [], "rolls fell under the floor")
	assert_eq(over_spread, [], "rolls went over base plus spread")
	assert_true(seen_low and seen_high, "1000 rolls never reached either end of the spread")


## The roll goes in `attribute_bonus` rather than onto the class, so the class
## spread stays readable underneath it. That separation is what lets a screen
## say where a number came from, and it is `PawnData`'s own stated reason for
## having the field.
func test_the_class_spread_is_still_readable_under_a_roll() -> void:
	var cls := Registry.get_class_def(&"warrior")
	var before := cls.attribute(CG.Attribute.STR)
	for s in 20:
		PawnFactory.make_rolled_pawn(&"warrior", &"p", "p", s)
	assert_eq(cls.attribute(CG.Attribute.STR), before, "rolling a pawn mutated its class")
	var pawn := PawnFactory.make_rolled_pawn(&"warrior", &"p", "p", 5)
	assert_eq(pawn.attribute(CG.Attribute.STR) - pawn.pawn_class.attribute(CG.Attribute.STR),
		int(pawn.attribute_bonus[CG.Attribute.STR]),
		"the delta a screen would show is not the roll")


## A rolled pawn is still equippable: the gear gate reads class tags, which a
## roll does not touch, and #131's own gear half must not have been undone.
func test_a_rolled_pawn_still_starts_in_gear_it_is_allowed_to_wear() -> void:
	for class_id in Registry.all_class_ids():
		for s in 20:
			var pawn := PawnFactory.make_rolled_pawn(class_id, &"p", "p", s)
			for piece in pawn.equipment():
				assert_true(piece.allows_class(pawn.pawn_class),
					"%s on seed %d starts with %s and could not equip it" % [class_id, s, piece.id])


func _all_attributes() -> Array:
	return [CG.Attribute.STR, CG.Attribute.DEX, CG.Attribute.AGI, CG.Attribute.CON,
		CG.Attribute.INT, CG.Attribute.ATN, CG.Attribute.WIS]
