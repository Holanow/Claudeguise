extends "res://Tests/TestCase.gd"

## Issue 916: an authored base item becomes a generated one. The roll's rates,
## its slot scoping, its determinism, and what a rolled affix does to a pawn.

const SLOTS: Array = [
	EquipmentDef.Slot.MAIN_HAND, EquipmentDef.Slot.OFF_HAND,
	EquipmentDef.Slot.HEAD, EquipmentDef.Slot.BODY, EquipmentDef.Slot.ACCESSORY,
]

func _base(slot: EquipmentDef.Slot) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = &"probe_base"
	e.display_name = "Probe"
	e.slot = slot
	return e

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func _affix(effect: AffixDef.Effect, value_min: float, value_max: float) -> AffixDef:
	var a := AffixDef.new()
	a.id = &"probe_affix"
	a.display_name = "Probe"
	a.effect = effect
	a.base_min = value_min
	a.base_max = value_max
	return a

# ---------------------------------------------------------------------------
# The rates
# ---------------------------------------------------------------------------

## The player, 2026-09-10: one affix about 40% of the time and two about 10%.
## 20000 rolls, so a one point tolerance is far outside the sampling noise of
## the rate itself rather than a threshold anybody tuned.
func test_floor_one_rolls_the_players_rates() -> void:
	var counts := [0, 0, 0, 0, 0]
	var rng := _rng(916)
	var base := _base(EquipmentDef.Slot.BODY)
	for i in 20000:
		counts[ItemRoller.roll(base, 1, rng).affixes.size()] += 1
	assert_almost_eq(float(counts[0]) / 20000.0, 0.5, 0.01, "half of floor 1 rolls none")
	assert_almost_eq(float(counts[1]) / 20000.0, 0.4, 0.01, "40% roll one")
	assert_almost_eq(float(counts[2]) / 20000.0, 0.1, 0.01, "10% roll two")
	assert_eq(counts[3], 0, "floor 1 never rolls three")
	assert_eq(counts[4], 0, "floor 1 never rolls four")

## Rarity is the affix count and nothing else stores it.
func test_rarity_is_the_affix_count() -> void:
	var base := _base(EquipmentDef.Slot.BODY)
	assert_eq(base.rarity(), EquipmentDef.Rarity.COMMON)
	var rng := _rng(5)
	var seen := {}
	for i in 400:
		var item := ItemRoller.roll(base, 1, rng)
		assert_eq(int(item.rarity()), item.affixes.size())
		seen[item.rarity()] = true
	assert_true(seen.has(EquipmentDef.Rarity.UNCOMMON) and seen.has(EquipmentDef.Rarity.RARE),
		"400 rolls should have produced both of floor 1's non-common tiers")

## A rolled piece says what it is in the picker, which lists by display name.
func test_a_rolled_piece_is_renamed_and_a_common_one_is_not() -> void:
	var base := _base(EquipmentDef.Slot.BODY)
	var rng := _rng(11)
	for i in 200:
		var item := ItemRoller.roll(base, 1, rng)
		if item.affixes.is_empty():
			assert_eq(item.display_name, "Probe")
		else:
			assert_eq(item.display_name,
				"%s Probe" % EquipmentDef.rarity_name(item.rarity()))

# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------

## The whole reason the roll takes an rng: #675 and #907 were both a seed taken
## from the clock.
func test_the_same_seed_rolls_the_same_items() -> void:
	var base := _base(EquipmentDef.Slot.ACCESSORY)
	var a := _rng(4242)
	var b := _rng(4242)
	for i in 200:
		var left := ItemRoller.roll(base, 1, a)
		var right := ItemRoller.roll(base, 1, b)
		assert_eq(left.affixes.size(), right.affixes.size())
		for n in left.affixes.size():
			assert_eq(left.affixes[n].affix.id, right.affixes[n].affix.id)
			assert_eq(left.affixes[n].value, right.affixes[n].value)

func test_a_different_seed_rolls_something_else() -> void:
	var base := _base(EquipmentDef.Slot.ACCESSORY)
	var a := _rng(1)
	var b := _rng(2)
	var differed := false
	for i in 200:
		var left := ItemRoller.roll(base, 1, a)
		var right := ItemRoller.roll(base, 1, b)
		if left.affixes.size() != right.affixes.size():
			differed = true
	assert_true(differed, "two seeds that never differ is a roll that reads nothing")

## `ItemLibrary` hands out one shared instance of every item, so a roll that
## wrote into its base would change every other copy in the game.
func test_a_roll_never_touches_the_base_item() -> void:
	var base := ItemLibrary.get_equipment(&"plate_mail")
	var name_before := base.display_name
	var rng := _rng(77)
	for i in 500:
		ItemRoller.roll(base, 1, rng)
	assert_eq(base.affixes.size(), 0, "the library's own plate mail gained an affix")
	assert_eq(base.display_name, name_before)

# ---------------------------------------------------------------------------
# Scoping
# ---------------------------------------------------------------------------

## A helm rolls from its own list, not a global one.
func test_every_rolled_affix_comes_from_that_slots_pool() -> void:
	var rng := _rng(31)
	for slot in SLOTS:
		var allowed := {}
		for a in AffixPools.for_slot(slot):
			allowed[a.id] = true
		for i in 500:
			for r in ItemRoller.roll(_base(slot), 1, rng).affixes:
				assert_true(allowed.has(r.affix.id),
					"%s rolled %s, which is not in its pool" % [slot, r.affix.id])

## One piece never rolls the same affix twice; the draw is without replacement.
func test_an_affix_never_lands_twice_on_one_piece() -> void:
	var rng := _rng(52)
	for slot in SLOTS:
		for i in 1000:
			var seen := {}
			for r in ItemRoller.roll(_base(slot), 1, rng).affixes:
				assert_false(seen.has(r.affix.id), "%s rolled twice" % r.affix.id)
				seen[r.affix.id] = true

## Every value lands inside the band that slot declares.
func test_every_value_is_inside_its_slots_band() -> void:
	var rng := _rng(63)
	for slot in SLOTS:
		for i in 500:
			for r in ItemRoller.roll(_base(slot), 1, rng).affixes:
				var band := AffixPools.draw_range(r.affix, slot)
				var unit := 100.0 if r.affix.is_fraction() else 1.0
				var drawn := int(round(r.value * unit))
				assert_true(drawn >= band.x and drawn <= band.y,
					"%s rolled %d outside [%d, %d]" % [r.affix.id, drawn, band.x, band.y])

## README: "a body always beats a ring at +HP". Bands, not averages -- the
## worst body roll must beat the best ring roll.
func test_a_body_always_beats_a_ring_at_life() -> void:
	var vital := AffixLibrary.get_affix(&"vital")
	var body := AffixPools.draw_range(vital, EquipmentDef.Slot.BODY)
	var ring := AffixPools.draw_range(vital, EquipmentDef.Slot.ACCESSORY)
	assert_true(body.x > ring.y,
		"body [%d, %d] must not overlap accessory [%d, %d]" % [body.x, body.y, ring.x, ring.y])

# ---------------------------------------------------------------------------
# Numbers now, verbs later
# ---------------------------------------------------------------------------

## Floor 1 rolls numbers only. Nothing authored is a verb yet, so the gate is
## proved against a fixture pool rather than against content that would pass it
## by accident.
func test_floor_one_never_rolls_a_verb() -> void:
	var verb := _affix(AffixDef.Effect.ATTRIBUTE_FLAT, 1, 2)
	verb.kind = AffixDef.Kind.VERB
	var pool: Array[AffixDef] = [verb]
	var rng := _rng(88)
	for i in 2000:
		assert_eq(ItemRoller.roll_from(_base(EquipmentDef.Slot.BODY), 1, rng, pool).affixes.size(), 0,
			"floor 1 drew a verb")

func test_a_deeper_floor_does_roll_a_verb() -> void:
	var verb := _affix(AffixDef.Effect.ATTRIBUTE_FLAT, 1, 2)
	verb.kind = AffixDef.Kind.VERB
	var pool: Array[AffixDef] = [verb]
	var rng := _rng(89)
	var drew := false
	for i in 200:
		if not ItemRoller.roll_from(_base(EquipmentDef.Slot.BODY), ItemRoller.VERB_UNLOCK_FLOOR,
				rng, pool).affixes.is_empty():
			drew = true
	assert_true(drew, "the verb gate opens at floor %d" % ItemRoller.VERB_UNLOCK_FLOOR)

## Every shipped affix is a number, which is what makes floor 1 playable at all.
func test_nothing_shipped_is_a_verb_yet() -> void:
	for id in AffixLibrary.all_ids():
		assert_eq(AffixLibrary.get_affix(id).kind, AffixDef.Kind.NUMBER,
			"%s is a verb and no floor rolls verbs yet" % id)

# ---------------------------------------------------------------------------
# What a rolled affix does to a pawn
# ---------------------------------------------------------------------------

func _pawn_wearing(item: EquipmentDef) -> PawnData:
	var p := PawnData.new()
	p.pawn_class = ClassLibrary.get_class_def(&"warrior")
	p.body = item
	return p

func _rolled(effect: AffixDef.Effect, value: float) -> EquipmentDef:
	var r := AffixRoll.new()
	r.affix = _affix(effect, value, value)
	r.value = value
	var e := _base(EquipmentDef.Slot.BODY)
	e.affixes = [r] as Array[AffixRoll]
	return e

func test_a_life_affix_raises_max_hp() -> void:
	var bare := _pawn_wearing(_base(EquipmentDef.Slot.BODY))
	var worn := _pawn_wearing(_rolled(AffixDef.Effect.MAX_HP_FLAT, 36.0))
	assert_eq(worn.max_hp(), bare.max_hp() + 36)

func test_an_attribute_affix_raises_that_attribute() -> void:
	var e := _base(EquipmentDef.Slot.BODY)
	var r := AffixRoll.new()
	r.affix = AffixLibrary.get_affix(&"tempered")
	r.value = 3.0
	e.affixes = [r] as Array[AffixRoll]
	var bare := _pawn_wearing(_base(EquipmentDef.Slot.BODY))
	var worn := _pawn_wearing(e)
	assert_almost_eq(worn.effective_attribute(CG.Attribute.STR),
		bare.effective_attribute(CG.Attribute.STR) + 3.0, 0.001)

## Within one piece base and affix sum, because they are the same piece of
## gear; across pieces `gear_damage_reduction` still takes the best.
func test_damage_reduction_sums_inside_a_piece_and_is_best_across_them() -> void:
	var body := _rolled(AffixDef.Effect.DAMAGE_REDUCTION, 0.06)
	body.damage_reduction = 0.05
	assert_almost_eq(body.total_damage_reduction(), 0.11, 0.0001)
	var pawn := _pawn_wearing(body)
	var shield := _base(EquipmentDef.Slot.OFF_HAND)
	shield.damage_reduction = 0.15
	pawn.off_hand = shield
	assert_almost_eq(pawn.gear_damage_reduction(), 0.15, 0.0001)

func test_a_damage_affix_multiplies_attack_power() -> void:
	var unit := CombatUnit.new()
	unit.id = 0
	unit.team = CG.Team.PLAYER
	unit.pawn = _pawn_wearing(_rolled(AffixDef.Effect.DAMAGE_PERCENT, 0.12))
	var action := ActionDef.new()
	action.id = &"probe_swing"
	action.effects = [HitEffect.new()] as Array[AbilityEffect]
	assert_almost_eq(AbilityModifiers.power_multiplier(unit, action), 1.12, 0.0001)

## The negative half: a pawn wearing an unrolled piece is exactly the pawn it
## was before this issue existed.
func test_an_unrolled_piece_changes_nothing() -> void:
	var item := _base(EquipmentDef.Slot.BODY)
	assert_eq(item.total_damage_reduction(), 0.0)
	assert_eq(item.affix_max_hp_flat(), 0.0)
	assert_eq(item.affix_power_multiplier(), 1.0)
	assert_eq(item.total_attribute_flat(CG.Attribute.STR), 0.0)
