extends "res://Tests/TestCase.gd"

## Balance formulas, tested against hand-built PawnData so this file needs
## nothing from CombatSim or Registry to run.

func _pawn(method: CG.Method, style: CG.Style, attrs: Dictionary) -> PawnData:
	var c := ClassDef.new()
	c.method = method
	c.style = style
	for k in attrs:
		c.base_attributes[ClassDef.ATTRIBUTE_NAME[k]] = attrs[k]
	c.resource_kind = CG.ResourceKind.MANA
	var p := PawnData.new()
	p.pawn_class = c
	return p


func test_max_hp_scales_with_con_and_str() -> void:
	var low := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 1, CG.Attribute.STR: 1})
	var high := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 9, CG.Attribute.STR: 9})
	assert_true(Balance.max_hp(high) > Balance.max_hp(low), "more CON/STR must mean more hp")
	assert_eq(Balance.max_hp(low), Balance.BASE_HP + 1 * Balance.HP_PER_CON + 1 * Balance.HP_PER_STR_BONUS)


func test_max_resource_scales_with_atn_and_int() -> void:
	var low := _pawn(CG.Method.MAGICAL, CG.Style.RANGED, {CG.Attribute.ATN: 1, CG.Attribute.INT: 1})
	var high := _pawn(CG.Method.MAGICAL, CG.Style.RANGED, {CG.Attribute.ATN: 9, CG.Attribute.INT: 9})
	assert_true(Balance.max_resource(high) > Balance.max_resource(low))


func test_move_speed_scales_with_agi_and_dex() -> void:
	var slow := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 1, CG.Attribute.DEX: 1})
	var fast := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 9, CG.Attribute.DEX: 9})
	assert_true(Balance.move_speed(fast) > Balance.move_speed(slow))


func test_attack_power_uses_str_for_martial_melee() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 6, CG.Attribute.DEX: 1, CG.Attribute.INT: 1})
	assert_almost_eq(Balance.attack_power(pawn, CG.DamageType.PHYSICAL), 6.0 * Balance.ATTACK_POWER_PER_POINT)


func test_attack_power_uses_dex_for_martial_ranged() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.RANGED, {CG.Attribute.STR: 1, CG.Attribute.DEX: 7, CG.Attribute.INT: 1})
	assert_almost_eq(Balance.attack_power(pawn, CG.DamageType.PHYSICAL), 7.0 * Balance.ATTACK_POWER_PER_POINT)


func test_attack_power_uses_int_for_magical_regardless_of_style() -> void:
	var melee := _pawn(CG.Method.MAGICAL, CG.Style.MELEE, {CG.Attribute.STR: 9, CG.Attribute.INT: 5})
	var ranged := _pawn(CG.Method.MAGICAL, CG.Style.RANGED, {CG.Attribute.STR: 9, CG.Attribute.INT: 5})
	assert_almost_eq(Balance.attack_power(melee, CG.DamageType.FIRE), 5.0 * Balance.ATTACK_POWER_PER_POINT)
	assert_almost_eq(Balance.attack_power(melee, CG.DamageType.FIRE), Balance.attack_power(ranged, CG.DamageType.FIRE))


func test_damage_reduction_zero_for_enemy_or_empty_unit() -> void:
	var u := CombatUnit.new()
	assert_almost_eq(Balance.damage_reduction(u), 0.0)


func test_damage_reduction_rises_with_con_and_caps() -> void:
	var u := CombatUnit.new()
	u.pawn = _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 500})
	assert_almost_eq(Balance.damage_reduction(u), Balance.NATURAL_DAMAGE_REDUCTION_CAP)


func test_damage_reduction_adds_shield_and_block_statuses() -> void:
	var u := CombatUnit.new()
	u.pawn = _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 0})
	var base := Balance.damage_reduction(u)
	u.statuses[CG.Status.SHIELD] = 999
	var with_shield := Balance.damage_reduction(u)
	assert_true(with_shield > base, "SHIELD must add reduction")
	u.statuses[CG.Status.BLOCK] = 999
	var with_both := Balance.damage_reduction(u)
	assert_true(with_both > with_shield, "BLOCK must stack more reduction")
	assert_true(with_both <= Balance.MAX_DAMAGE_REDUCTION)


## Issue 12: MARKED is the Spotter's whole mechanical effect -- a marked
## target must measurably take more damage (criterion 4), which for
## damage_reduction means less of it, or the mark does nothing.
func test_marked_status_lowers_damage_reduction() -> void:
	var u := CombatUnit.new()
	u.pawn = _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 20})
	var base := Balance.damage_reduction(u)
	u.statuses[CG.Status.MARKED] = 999
	var marked := Balance.damage_reduction(u)
	assert_true(marked < base, "MARKED must lower damage reduction, so a marked unit takes more damage")


## Issue 12: previously `damage_reduction()` returned 0.0 outright for any
## unit with no `pawn` -- every enemy -- because `SimDeps` read
## `EnemyDef.damage_reduction` directly and never called this function for
## one. MARKED lives on `CombatUnit` and applies to enemies far more often
## than to a pawn, so an enemy must actually flow through here now.
func test_enemy_units_read_their_own_damage_reduction_through_balance() -> void:
	var u := CombatUnit.new()
	u.enemy_id = &"the_warden"
	var warden := EnemyLibrary.get_enemy(&"the_warden")
	assert_not_null(warden, "expected the_warden to be registered")
	assert_almost_eq(Balance.damage_reduction(u), warden.damage_reduction)


## The same enemy, marked, must take more damage than its own unmarked
## baseline -- not just "less than some pawn's," which the two tests above
## could each pass in isolation without this ever being true together.
func test_a_marked_enemy_takes_more_damage_than_the_same_enemy_unmarked() -> void:
	var u := CombatUnit.new()
	u.enemy_id = &"the_warden"
	var base := Balance.damage_reduction(u)
	u.statuses[CG.Status.MARKED] = 999
	var marked := Balance.damage_reduction(u)
	assert_true(marked < base, "a marked the_warden must have lower damage reduction than an unmarked the_warden")


func test_plan_block_budget_tracks_wis() -> void:
	var low := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.WIS: 2})
	var high := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.WIS: 6})
	assert_eq(Balance.plan_block_budget(low), 2)
	assert_eq(Balance.plan_block_budget(high), 6)


## Issue 269. This was the one formula in the file reading `pawn.attribute()`
func test_plan_block_budget_counts_equipment_wis() -> void:
	var pawn := _pawn(CG.Method.MAGICAL, CG.Style.RANGED, {CG.Attribute.WIS: 6})
	assert_eq(Balance.plan_block_budget(pawn), 6, "the bare pawn is its class's WIS")
	var armor := EquipmentDef.new()
	armor.slot = EquipmentDef.Slot.BODY
	armor.attribute_flat = {CG.Attribute.WIS: 2}
	pawn.body = armor
	assert_eq(Balance.plan_block_budget(pawn), 8, "two points of WIS on armor must buy two blocks")
	pawn.body = null
	assert_eq(Balance.plan_block_budget(pawn), 6, "and taking it off must give them back")


## The negative half: equipment carrying no WIS must not move the budget. A
## reader that returned any equipment total at all would pass the test above.
func test_plan_block_budget_ignores_equipment_without_wis() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.WIS: 4})
	var armor := EquipmentDef.new()
	armor.slot = EquipmentDef.Slot.BODY
	armor.attribute_flat = {CG.Attribute.CON: 5, CG.Attribute.STR: 5}
	pawn.body = armor
	assert_eq(Balance.plan_block_budget(pawn), 4, "CON and STR buy no plan blocks")


func test_plan_block_budget_never_zero() -> void:
	var no_wis := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {})
	assert_true(Balance.plan_block_budget(no_wis) >= 1)


func test_scale_action_ticks_speeds_up_with_agi_and_has_a_floor() -> void:
	var slow := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 0})
	var fast := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 9999})
	assert_eq(Balance.scale_action_ticks(20, slow), 20)
	assert_eq(Balance.scale_action_ticks(20, fast), 2, "capped at MAX_AGI_TICK_SCALE = 0.9")


func test_scale_action_ticks_never_reaches_zero() -> void:
	var fast := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 9999})
	assert_true(Balance.scale_action_ticks(1, fast) >= 1)


func test_attack_power_with_no_rng_is_the_flat_deterministic_number() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 6})
	var expected := 6.0 * Balance.ATTACK_POWER_PER_POINT
	assert_almost_eq(Balance.attack_power(pawn, CG.DamageType.PHYSICAL), expected)
	assert_almost_eq(Balance.attack_power(pawn, CG.DamageType.PHYSICAL, null), expected)


func test_attack_power_with_rng_varies_within_the_declared_spread() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 6})
	var base := 6.0 * Balance.ATTACK_POWER_PER_POINT
	var lo := base * (1.0 - Balance.ATTACK_VARIANCE_SPREAD)
	var hi := base * (1.0 + Balance.ATTACK_VARIANCE_SPREAD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var saw_below_flat := false
	var saw_above_flat := false
	for i in 50:
		var rolled := Balance.attack_power(pawn, CG.DamageType.PHYSICAL, rng)
		assert_true(rolled >= lo - 0.001 and rolled <= hi + 0.001, "roll %f outside [%f, %f]" % [rolled, lo, hi])
		if rolled < base:
			saw_below_flat = true
		if rolled > base:
			saw_above_flat = true
	assert_true(saw_below_flat and saw_above_flat, "50 rolls should land on both sides of the flat value")


func test_mana_regenerates_slower_than_energy() -> void:
	var mana_unit := CombatUnit.new()
	mana_unit.resource_kind = CG.ResourceKind.MANA
	mana_unit.resource_max = 100
	var energy_unit := CombatUnit.new()
	energy_unit.resource_kind = CG.ResourceKind.ENERGY
	energy_unit.resource_max = 100
	var mana_rate := Balance.resource_regen_per_tick(mana_unit)
	var energy_rate := Balance.resource_regen_per_tick(energy_unit)
	assert_true(mana_rate > 0.0)
	assert_true(energy_rate > mana_rate, "Energy should recover faster than Mana per README.md")


func test_rage_never_regenerates_on_a_timer() -> void:
	var rage_unit := CombatUnit.new()
	rage_unit.resource_kind = CG.ResourceKind.RAGE
	rage_unit.resource_max = 100
	assert_almost_eq(Balance.resource_regen_per_tick(rage_unit), 0.0)


func test_rage_gain_per_attack_only_applies_to_rage() -> void:
	var rage_unit := CombatUnit.new()
	rage_unit.resource_kind = CG.ResourceKind.RAGE
	rage_unit.resource_max = 100
	assert_true(Balance.rage_gain_per_attack(rage_unit) > 0.0)

	var mana_unit := CombatUnit.new()
	mana_unit.resource_kind = CG.ResourceKind.MANA
	mana_unit.resource_max = 100
	assert_almost_eq(Balance.rage_gain_per_attack(mana_unit), 0.0)


func test_attack_power_variance_is_reproducible_from_the_same_seed() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 6})
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 999
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 999
	for i in 10:
		assert_almost_eq(
			Balance.attack_power(pawn, CG.DamageType.PHYSICAL, rng_a),
			Balance.attack_power(pawn, CG.DamageType.PHYSICAL, rng_b),
			0.0001, "roll %d diverged between two RNGs seeded identically" % i
		)


## Issue 121: **BURN left this function and the removal is the point.** Its rate
## is a fraction of the hit that lit it, which is the magnitude term, and leaving
## a percent-of-max-health rate here as well would make burn do both at once.
func test_status_damage_per_tick_applies_to_poison_and_nothing_else() -> void:
	var u := CombatUnit.new()
	u.hp_max = 100
	assert_true(Balance.status_damage_per_tick(u, CG.Status.POISON) > 0.0)
	for other in [CG.Status.SHIELD, CG.Status.BLEED, CG.Status.STUN, CG.Status.HASTE, CG.Status.MARKED, CG.Status.BURN]:
		assert_almost_eq(Balance.status_damage_per_tick(u, other), 0.0, 0.0001, "%s should deal no flat tick damage" % other)

## The other half, so "burn was removed" cannot be satisfied by burn doing
## nothing at all -- which is exactly what a half-landed version of this change
## looks like.
func test_burn_gets_its_rate_from_the_hit_that_applied_it_instead() -> void:
	var u := CombatUnit.new()
	u.hp_max = 100
	assert_true(Balance.status_damage_per_magnitude(u, CG.Status.BURN) > 0.0,
		"burn came off the flat rate and got nothing back; it now deals nothing at all")
	for other in [CG.Status.SHIELD, CG.Status.POISON, CG.Status.STUN, CG.Status.HASTE, CG.Status.MARKED]:
		assert_almost_eq(Balance.status_damage_per_magnitude(u, other), 0.0, 0.0001,
			"%s should draw nothing from a stored magnitude" % other)


func test_status_damage_per_tick_scales_with_victim_max_hp() -> void:
	var small := CombatUnit.new()
	small.hp_max = 50
	var large := CombatUnit.new()
	large.hp_max = 500
	# Proportional, not flat: a bigger unit takes a bigger raw number so the
	# same status is equally scary as a fraction of hp for everyone. POISON
	# rather than BURN since issue 121 -- burn scales with the hit that lit it
	# instead, which is a different and deliberate rule.
	assert_almost_eq(
		Balance.status_damage_per_tick(large, CG.Status.POISON),
		Balance.status_damage_per_tick(small, CG.Status.POISON) * 10.0,
		0.01
	)


func test_haste_tick_scale_speeds_up_and_never_reaches_zero() -> void:
	var u := CombatUnit.new()
	var scale := Balance.haste_tick_scale(u)
	assert_true(scale < 1.0, "HASTE should speed a unit up")
	assert_true(scale > 0.0, "a multiplier of 0 would make an action instant")


## Issue 52: the real slowed_speed_scale SimDeps was waiting on --
## `_default_slowed_speed_scale`'s own doc comment names this exact function.
func test_slowed_speed_scale_slows_and_never_reaches_zero() -> void:
	var u := CombatUnit.new()
	var scale := Balance.slowed_speed_scale(u)
	assert_true(scale < 1.0, "SLOWED should slow a unit down")
	assert_true(scale > 0.0, "a multiplier of 0 would make SLOWED indistinguishable from STUN")


## Issue 39: Balance.attribute() is the single place equipment's
## attribute_flat/attribute_percent apply. Bare pawn.attribute() (Core) must
## stay equipment-blind so nothing can read a stat twice by going around this.

func test_attribute_with_no_equipment_matches_the_bare_class_value() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 5})
	assert_almost_eq(Balance.attribute(pawn, CG.Attribute.STR), 5.0)


func test_weapon_attribute_percent_multiplies_the_base_stat() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 10})
	var weapon := EquipmentDef.new()
	weapon.slot = EquipmentDef.Slot.MAIN_HAND
	weapon.attribute_percent = {CG.Attribute.STR: 0.20}
	pawn.main_hand = weapon
	assert_almost_eq(Balance.attribute(pawn, CG.Attribute.STR), 12.0, 0.001, "10 STR +20%% should be 12")


func test_armor_attribute_flat_adds_before_percent() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 10})
	var armor := EquipmentDef.new()
	armor.slot = EquipmentDef.Slot.BODY
	armor.attribute_flat = {CG.Attribute.CON: 3}
	armor.attribute_percent = {CG.Attribute.CON: 0.10}
	pawn.body = armor
	assert_almost_eq(Balance.attribute(pawn, CG.Attribute.CON), 14.3, 0.001, "(10+3) * 1.10 = 14.3")


func test_equipped_weapon_raises_max_hp_through_str() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 5, CG.Attribute.STR: 10})
	var bare_hp := Balance.max_hp(pawn)
	var weapon := EquipmentDef.new()
	weapon.slot = EquipmentDef.Slot.MAIN_HAND
	weapon.attribute_percent = {CG.Attribute.STR: 0.50}
	pawn.main_hand = weapon
	assert_true(Balance.max_hp(pawn) > bare_hp, "a weapon buffing STR should raise max hp through HP_PER_STR_BONUS")


func test_accessory_attribute_percent_raises_attack_power() -> void:
	var pawn := _pawn(CG.Method.MAGICAL, CG.Style.RANGED, {CG.Attribute.INT: 10})
	var bare := Balance.attack_power(pawn, CG.DamageType.FIRE)
	var accessory := EquipmentDef.new()
	accessory.slot = EquipmentDef.Slot.ACCESSORY
	accessory.attribute_percent = {CG.Attribute.INT: 0.30}
	pawn.accessory = accessory
	assert_true(Balance.attack_power(pawn, CG.DamageType.FIRE) > bare, "an accessory buffing INT should raise a Magical class's attack power")


func test_three_equipped_pieces_all_contribute() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 10})
	var weapon := EquipmentDef.new()
	weapon.attribute_flat = {CG.Attribute.STR: 1}
	var armor := EquipmentDef.new()
	armor.attribute_flat = {CG.Attribute.STR: 1}
	var accessory := EquipmentDef.new()
	accessory.attribute_flat = {CG.Attribute.STR: 1}
	pawn.main_hand = weapon
	pawn.body = armor
	pawn.accessory = accessory
	assert_almost_eq(Balance.attribute(pawn, CG.Attribute.STR), 13.0, 0.001, "all three slots should stack their flat bonus")


## Issue 45: between-room recovery. README's Healer text ("meant to restore
## health and revive allies") is the reasoning; these prove the numbers.

func test_between_room_heal_restores_a_fraction_of_what_is_missing() -> void:
	var healed := Balance.between_room_heal(20, 100, false)
	assert_true(healed > 20, "a party at 20/100 should recover something")
	assert_true(healed < 100, "recovery should not be a full heal -- a room still has to cost something")


func test_a_living_healer_recovers_more() -> void:
	var without_healer := Balance.between_room_heal(20, 100, false)
	var with_healer := Balance.between_room_heal(20, 100, true)
	assert_true(with_healer > without_healer, "a Healer in the party should recover more between rooms")


func test_between_room_heal_never_exceeds_max_hp() -> void:
	var healed := Balance.between_room_heal(95, 100, true)
	assert_true(healed <= 100, "recovery should never push a pawn above its own max hp")


func test_between_room_heal_leaves_a_full_health_pawn_alone() -> void:
	assert_eq(Balance.between_room_heal(100, 100, true), 100)


func test_revive_only_happens_with_a_living_healer() -> void:
	assert_eq(Balance.revive_hp(100, false), 0, "no Healer, no revival -- a dead pawn should stay dead")
	assert_true(Balance.revive_hp(100, true) > 0, "a living Healer should be able to revive a dead pawn")


func test_revive_hp_is_a_fraction_of_max_not_a_free_full_heal() -> void:
	var revived := Balance.revive_hp(200, true)
	assert_true(revived > 0 and revived < 200, "a revival should be a real fraction of max hp, not full and not zero")


## Found mid-#30: resource was never recovered between rooms the way hp was,
## and it was the thing actually wearing a party down (hp only drifted to
## 71-84% by the boss, resource crashed to 7-23%). These mirror
## between_room_heal's own tests -- same shape, different economy.

func test_between_room_resource_recover_restores_a_fraction_of_what_is_missing() -> void:
	var recovered := Balance.between_room_resource_recover(10, 100)
	assert_true(recovered > 10, "a pawn at 10/100 resource should recover something")
	assert_true(recovered < 100, "recovery should not be a full restore -- a room still has to cost something")


func test_between_room_resource_recover_never_exceeds_max() -> void:
	var recovered := Balance.between_room_resource_recover(95, 100)
	assert_true(recovered <= 100, "recovery should never push a pawn above its own max resource")


func test_between_room_resource_recover_leaves_a_full_pawn_alone() -> void:
	assert_eq(Balance.between_room_resource_recover(100, 100), 100)


func test_between_room_resource_recover_never_lowers_resource() -> void:
	# hp <= 0 is a real case for between_room_heal (a pawn between death and
	# revival); resource has no equivalent floor below 0 in this game, but
	# the same "never returns below what was passed in" guarantee should
	# hold regardless of how small the input is.
	assert_eq(Balance.between_room_resource_recover(0, 100), int(round(100.0 * Balance.BASE_RESOURCE_RECOVERY_FRACTION)))
