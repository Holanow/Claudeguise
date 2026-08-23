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


## Issue 485: the pool is roughly the class's own total, not exactly it. The
## player asked for "roughly the same size", so exactness would be the defect.
func test_the_pool_is_roughly_but_not_exactly_the_class_total() -> void:
	var over := []
	for class_id in Registry.all_class_ids():
		var cls := Registry.get_class_def(class_id)
		var expected := PawnFactory.pool_size(cls)
		var sizes := {}
		for s in 200:
			var pawn := PawnFactory.make_rolled_pawn(class_id, &"p", "p", s)
			var total := 0
			for a in PawnFactory.ROLLED_ATTRIBUTES:
				total += pawn.attribute(a)
			if absi(total - expected) > PawnFactory.POOL_JITTER:
				over.append("%s distributed %d against a pool of %d" % [class_id, total, expected])
			sizes[total] = true
		assert_true(sizes.size() > 1, "%s's pool is exactly fixed; 'roughly' was lost" % class_id)
	assert_eq(over, [], "a pool went outside its jitter")


## Every point lands somewhere, so a pool is distributed rather than partly
## discarded. This is what makes two pawns worth about the same.
func test_no_point_is_lost_between_the_pool_and_the_pawn() -> void:
	var bad := []
	for class_id in Registry.all_class_ids():
		for s in 50:
			var pawn := PawnFactory.make_rolled_pawn(class_id, &"p", "p", s)
			var total := 0
			for a in PawnFactory.ROLLED_ATTRIBUTES:
				var v := pawn.attribute(a)
				if v < 0:
					bad.append("%s %s negative" % [class_id, CG.attribute_name(a)])
				total += v
			if total <= 0:
				bad.append("%s distributed nothing on seed %d" % [class_id, s])
	assert_eq(bad, [], "points went missing between the pool and the pawn")


## The failure the weighting exists to prevent: a Warrior must not roll into a
## caster stat line. Asserted on the mean rather than on any single pawn,
## because a multinomial has a tail and "never" is not a property it has; the
## per-sample misreads are printed instead. Issue 485 carries the reasoning.
func test_a_rolled_pawn_reads_as_its_class_on_average() -> void:
	var confusions := {}
	var failures := []
	for class_id in Registry.all_class_ids():
		var own := _mean_distance(class_id, class_id)
		for other in Registry.all_class_ids():
			if other == class_id:
				continue
			var to_other := _mean_distance(class_id, other)
			if own >= to_other:
				failures.append("%s sits %.1f from itself and %.1f from %s" % [class_id, own, to_other, other])
		for s in 120:
			var nearest := _nearest_class(PawnFactory.make_rolled_pawn(class_id, &"p", "p", s))
			if nearest != class_id:
				confusions[[class_id, nearest]] = int(confusions.get([class_id, nearest], 0)) + 1
	print("nearest-class misreads out of 120 a class: %s" % [confusions])
	assert_eq(failures, [], "a class's rolled pawns are nearer another class's baseline on average")


## And the hard version of the same thing: the attribute a class attacks with
## can never reach zero, because a pawn that deals no damage is not a pawn.
## `Balance.attack_power` picks it off method and style.
func test_the_attribute_a_class_attacks_with_never_reaches_zero() -> void:
	var zeroed := []
	for class_id in Registry.all_class_ids():
		var cls := Registry.get_class_def(class_id)
		var attack_attr := _attack_attribute(cls)
		for s in 300:
			var pawn := PawnFactory.make_rolled_pawn(class_id, &"p", "p", s)
			if pawn.attribute(attack_attr) <= 0:
				zeroed.append("%s %s on seed %d" % [class_id, CG.attribute_name(attack_attr), s])
	assert_eq(zeroed, [], "a class rolled the attribute it attacks with to zero")


## Issue 484's asymmetry, re-measured under the new shape rather than assumed
## to have gone. A stat a class is not weighted toward should sit near its
## baseline, not drift above it.
func test_a_low_attribute_no_longer_drifts_upward() -> void:
	var worst := 0.0
	var worst_name := ""
	for class_id in Registry.all_class_ids():
		var cls := Registry.get_class_def(class_id)
		var sums := {}
		for s in 300:
			var pawn := PawnFactory.make_rolled_pawn(class_id, &"p", "p", s)
			for a in PawnFactory.ROLLED_ATTRIBUTES:
				sums[a] = float(sums.get(a, 0.0)) + float(pawn.attribute(a))
		for a in PawnFactory.ROLLED_ATTRIBUTES:
			var mean := float(sums[a]) / 300.0
			var drift: float = mean - float(cls.attribute(a))
			if absf(drift) > absf(worst):
				worst = drift
				worst_name = "%s %s base %d mean %.2f" % [class_id, CG.attribute_name(a), cls.attribute(a), mean]
	print("largest mean drift from baseline: %+.2f (%s)" % [worst, worst_name])
	assert_true(absf(worst) < 0.5, "an attribute drifts %+.2f from its baseline: %s" % [worst, worst_name])


func _attack_attribute(cls: ClassDef) -> CG.Attribute:
	if cls.method == CG.Method.MAGICAL:
		return CG.Attribute.INT
	return CG.Attribute.STR if cls.style == CG.Style.MELEE else CG.Attribute.DEX

func _nearest_class(pawn: PawnData) -> StringName:
	var best := &""
	var best_d := 1 << 30
	for class_id in Registry.all_class_ids():
		var cls := Registry.get_class_def(class_id)
		var d := 0
		for a in PawnFactory.ROLLED_ATTRIBUTES:
			d += absi(pawn.attribute(a) - cls.attribute(a))
		if d < best_d:
			best_d = d
			best = class_id
	return best

func _class_distance(a_id: StringName, b_id: StringName) -> int:
	var a := Registry.get_class_def(a_id)
	var b := Registry.get_class_def(b_id)
	var d := 0
	for attr in PawnFactory.ROLLED_ATTRIBUTES:
		d += absi(a.attribute(attr) - b.attribute(attr))
	return d


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

## Mean L1 distance from `class_id`'s rolled pawns to `against`'s baseline.
func _mean_distance(class_id: StringName, against: StringName) -> float:
	var target := Registry.get_class_def(against)
	var total := 0
	for s in 120:
		var pawn := PawnFactory.make_rolled_pawn(class_id, &"p", "p", s)
		for a in PawnFactory.ROLLED_ATTRIBUTES:
			total += absi(pawn.attribute(a) - target.attribute(a))
	return float(total) / 120.0
