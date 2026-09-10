extends "res://Tests/TestCase.gd"

## PawnData's derived numbers, tested against hand-built PawnData so this file needs
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
	assert_true(high.max_hp() > low.max_hp(), "more CON/STR must mean more hp")
	assert_eq(low.max_hp(), PawnData.BASE_HP + 1 * PawnData.HP_PER_CON + 1 * PawnData.HP_PER_STR_BONUS)


func test_max_resource_scales_with_atn_and_int() -> void:
	var low := _pawn(CG.Method.MAGICAL, CG.Style.RANGED, {CG.Attribute.ATN: 1, CG.Attribute.INT: 1})
	var high := _pawn(CG.Method.MAGICAL, CG.Style.RANGED, {CG.Attribute.ATN: 9, CG.Attribute.INT: 9})
	assert_true(high.max_resource() > low.max_resource())


func test_move_speed_scales_with_agi_and_dex() -> void:
	var slow := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 1, CG.Attribute.DEX: 1})
	var fast := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 9, CG.Attribute.DEX: 9})
	assert_true(fast.move_speed() > slow.move_speed())


func test_attack_power_uses_str_for_martial_melee() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 6, CG.Attribute.DEX: 1, CG.Attribute.INT: 1})
	assert_almost_eq(pawn.attack_power(CG.DamageType.PHYSICAL), 6.0 * PawnData.ATTACK_POWER_PER_POINT)


func test_attack_power_uses_dex_for_martial_ranged() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.RANGED, {CG.Attribute.STR: 1, CG.Attribute.DEX: 7, CG.Attribute.INT: 1})
	assert_almost_eq(pawn.attack_power(CG.DamageType.PHYSICAL), 7.0 * PawnData.ATTACK_POWER_PER_POINT)


func test_attack_power_uses_int_for_magical_regardless_of_style() -> void:
	var melee := _pawn(CG.Method.MAGICAL, CG.Style.MELEE, {CG.Attribute.STR: 9, CG.Attribute.INT: 5})
	var ranged := _pawn(CG.Method.MAGICAL, CG.Style.RANGED, {CG.Attribute.STR: 9, CG.Attribute.INT: 5})
	assert_almost_eq(melee.attack_power(CG.DamageType.FIRE), 5.0 * PawnData.ATTACK_POWER_PER_POINT)
	assert_almost_eq(melee.attack_power(CG.DamageType.FIRE), ranged.attack_power(CG.DamageType.FIRE))


func test_damage_reduction_zero_for_enemy_or_empty_unit() -> void:
	var u := CombatUnit.new()
	assert_almost_eq(SimDeps._default_damage_reduction(u), 0.0)


func test_damage_reduction_rises_with_con_and_caps() -> void:
	var u := CombatUnit.new()
	u.pawn = _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 500})
	assert_almost_eq(SimDeps._default_damage_reduction(u), PawnData.NATURAL_DAMAGE_REDUCTION_CAP)


func test_damage_reduction_adds_shield_and_block_statuses() -> void:
	var u := CombatUnit.new()
	u.pawn = _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 0})
	var base := SimDeps._default_damage_reduction(u)
	u.statuses[CG.Status.SHIELD] = 999
	var with_shield := SimDeps._default_damage_reduction(u)
	assert_true(with_shield > base, "SHIELD must add reduction")
	u.statuses[CG.Status.BLOCK] = 999
	var with_both := SimDeps._default_damage_reduction(u)
	assert_true(with_both > with_shield, "BLOCK must stack more reduction")
	assert_true(with_both <= SimDeps.MAX_DAMAGE_REDUCTION)


## Issue 12: MARKED is the Spotter's whole mechanical effect -- a marked
## target must measurably take more damage (criterion 4), which for
## damage_reduction means less of it, or the mark does nothing.
func test_marked_status_lowers_damage_reduction() -> void:
	var u := CombatUnit.new()
	u.pawn = _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 20})
	var base := SimDeps._default_damage_reduction(u)
	u.statuses[CG.Status.MARKED] = 999
	var marked := SimDeps._default_damage_reduction(u)
	assert_true(marked < base, "MARKED must lower damage reduction, so a marked unit takes more damage")


## Issue 12: previously `damage_reduction()` returned 0.0 outright for any
## unit with no `pawn` -- every enemy -- because `SimDeps` read
## `EnemyDef.damage_reduction` directly and never called this function for
## one. MARKED lives on `CombatUnit` and applies to enemies far more often
## than to a pawn, so an enemy must actually flow through here now.
func test_enemy_units_read_their_own_damage_reduction_through_the_seam() -> void:
	var u := CombatUnit.new()
	u.enemy_id = &"the_warden"
	var warden := EnemyLibrary.get_enemy(&"the_warden")
	assert_not_null(warden, "expected the_warden to be registered")
	assert_almost_eq(SimDeps._default_damage_reduction(u), warden.damage_reduction)


## The same enemy, marked, must take more damage than its own unmarked
## baseline -- not just "less than some pawn's," which the two tests above
## could each pass in isolation without this ever being true together.
func test_a_marked_enemy_takes_more_damage_than_the_same_enemy_unmarked() -> void:
	var u := CombatUnit.new()
	u.enemy_id = &"the_warden"
	var base := SimDeps._default_damage_reduction(u)
	u.statuses[CG.Status.MARKED] = 999
	var marked := SimDeps._default_damage_reduction(u)
	assert_true(marked < base, "a marked the_warden must have lower damage reduction than an unmarked the_warden")


func test_scale_action_ticks_speeds_up_with_agi_and_has_a_floor() -> void:
	var slow := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 0})
	var fast := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 9999})
	assert_eq(slow.scale_action_ticks(20), 20)
	assert_eq(fast.scale_action_ticks(20), 2, "capped at MAX_AGI_TICK_SCALE = 0.9")


func test_scale_action_ticks_never_reaches_zero() -> void:
	var fast := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 9999})
	assert_true(fast.scale_action_ticks(1) >= 1)


func test_attack_power_with_no_rng_is_the_flat_deterministic_number() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 6})
	var expected := 6.0 * PawnData.ATTACK_POWER_PER_POINT
	assert_almost_eq(pawn.attack_power(CG.DamageType.PHYSICAL), expected)
	assert_almost_eq(pawn.attack_power(CG.DamageType.PHYSICAL, null), expected)


func test_attack_power_with_rng_varies_within_the_declared_spread() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 6})
	var base := 6.0 * PawnData.ATTACK_POWER_PER_POINT
	var lo := base * (1.0 - PawnData.ATTACK_VARIANCE_SPREAD)
	var hi := base * (1.0 + PawnData.ATTACK_VARIANCE_SPREAD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var saw_below_flat := false
	var saw_above_flat := false
	for i in 50:
		var rolled := pawn.attack_power(CG.DamageType.PHYSICAL, rng)
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
	var mana_rate := SimDeps._default_resource_regen_per_tick(mana_unit)
	var energy_rate := SimDeps._default_resource_regen_per_tick(energy_unit)
	assert_true(mana_rate > 0.0)
	assert_true(energy_rate > mana_rate, "Energy should recover faster than Mana per README.md")


func test_rage_never_regenerates_on_a_timer() -> void:
	var rage_unit := CombatUnit.new()
	rage_unit.resource_kind = CG.ResourceKind.RAGE
	rage_unit.resource_max = 100
	assert_almost_eq(SimDeps._default_resource_regen_per_tick(rage_unit), 0.0)


## Issue 746: a focus's `resource_regen_percent_bonus` widens the rate rather
## than replacing it -- a bare unit and one carrying the bonus should differ by
## exactly the bonus, converted the same way the base rate is.
func test_equipment_resource_regen_bonus_widens_the_rate() -> void:
	var bare := CombatUnit.new()
	bare.resource_kind = CG.ResourceKind.MANA
	bare.resource_max = 100
	var bare_rate := SimDeps._default_resource_regen_per_tick(bare)

	var focused := CombatUnit.new()
	focused.resource_kind = CG.ResourceKind.MANA
	focused.resource_max = 100
	var pawn := PawnData.new()
	var focus := EquipmentDef.new()
	focus.resource_regen_percent_bonus = 2.0
	pawn.off_hand = focus
	focused.pawn = pawn
	var focused_rate := SimDeps._default_resource_regen_per_tick(focused)

	assert_true(focused_rate > bare_rate, "a focus must raise the regen rate")
	var expected_delta := 100.0 * (2.0 / 100.0) / float(CG.TICKS_PER_SECOND)
	assert_almost_eq(focused_rate - bare_rate, expected_delta, 0.0001)


## And a RAGE unit stays at 0.0 even carrying the bonus -- Rage never rises on
## a timer, per README.md, and equipment must not open a second door to that.
func test_equipment_resource_regen_bonus_does_not_move_rage() -> void:
	var rage_unit := CombatUnit.new()
	rage_unit.resource_kind = CG.ResourceKind.RAGE
	rage_unit.resource_max = 100
	var pawn := PawnData.new()
	var focus := EquipmentDef.new()
	focus.resource_regen_percent_bonus = 2.0
	pawn.off_hand = focus
	rage_unit.pawn = pawn
	assert_almost_eq(SimDeps._default_resource_regen_per_tick(rage_unit), 0.0, 0.0001)


func test_rage_gain_per_attack_only_applies_to_rage() -> void:
	var rage_unit := CombatUnit.new()
	rage_unit.resource_kind = CG.ResourceKind.RAGE
	rage_unit.resource_max = 100
	assert_true(SimDeps._default_rage_gain_on_attack(rage_unit) > 0.0)

	var mana_unit := CombatUnit.new()
	mana_unit.resource_kind = CG.ResourceKind.MANA
	mana_unit.resource_max = 100
	assert_almost_eq(SimDeps._default_rage_gain_on_attack(mana_unit), 0.0)


func test_attack_power_variance_is_reproducible_from_the_same_seed() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 6})
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 999
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 999
	for i in 10:
		assert_almost_eq(
			pawn.attack_power(CG.DamageType.PHYSICAL, rng_a),
			pawn.attack_power(CG.DamageType.PHYSICAL, rng_b),
			0.0001, "roll %d diverged between two RNGs seeded identically" % i
		)


## Issue 121: **BURN left this function and the removal is the point.** Its rate
## is a fraction of the hit that lit it, which is the magnitude term, and leaving
## a percent-of-max-health rate here as well would make burn do both at once.
func test_status_damage_per_tick_applies_to_poison_and_nothing_else() -> void:
	var u := CombatUnit.new()
	u.hp_max = 100
	assert_true(StatusLibrary.of(CG.Status.POISON).damage_per_tick(u.hp_max) > 0.0)
	for other in [CG.Status.SHIELD, CG.Status.BLEED, CG.Status.STUN, CG.Status.HASTE, CG.Status.MARKED, CG.Status.BURN]:
		assert_almost_eq(StatusLibrary.of(other).damage_per_tick(u.hp_max), 0.0, 0.0001, "%s should deal no flat tick damage" % other)

## The other half, so "burn was removed" cannot be satisfied by burn doing
## nothing at all -- which is exactly what a half-landed version of this change
## looks like.
func test_burn_gets_its_rate_from_the_hit_that_applied_it_instead() -> void:
	var u := CombatUnit.new()
	u.hp_max = 100
	assert_true(StatusLibrary.of(CG.Status.BURN).damage_per_magnitude_per_tick > 0.0,
		"burn came off the flat rate and got nothing back; it now deals nothing at all")
	for other in [CG.Status.SHIELD, CG.Status.POISON, CG.Status.STUN, CG.Status.HASTE, CG.Status.MARKED]:
		assert_almost_eq(StatusLibrary.of(other).damage_per_magnitude_per_tick, 0.0, 0.0001,
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
		StatusLibrary.of(CG.Status.POISON).damage_per_tick(large.hp_max),
		StatusLibrary.of(CG.Status.POISON).damage_per_tick(small.hp_max) * 10.0,
		0.01
	)


func test_haste_tick_scale_speeds_up_and_never_reaches_zero() -> void:
	var u := CombatUnit.new()
	var scale := StatusLibrary.of(CG.Status.HASTE).tick_scale
	assert_true(scale < 1.0, "HASTE should speed a unit up")
	assert_true(scale > 0.0, "a multiplier of 0 would make an action instant")


## Issue 52: the real slowed_speed_scale SimDeps was waiting on --
## `_default_slowed_speed_scale`'s own doc comment names this exact function.
func test_slowed_speed_scale_slows_and_never_reaches_zero() -> void:
	var u := CombatUnit.new()
	var scale := StatusLibrary.of(CG.Status.SLOWED).speed_scale
	assert_true(scale < 1.0, "SLOWED should slow a unit down")
	assert_true(scale > 0.0, "a multiplier of 0 would make SLOWED indistinguishable from STUN")


## Issue 39: `PawnData.effective_attribute` is the single place equipment's
## attribute_flat/attribute_percent apply. Bare pawn.attribute() (Core) must
## stay equipment-blind so nothing can read a stat twice by going around this.

func test_attribute_with_no_equipment_matches_the_bare_class_value() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 5})
	assert_almost_eq(pawn.effective_attribute(CG.Attribute.STR), 5.0)


func test_weapon_attribute_percent_multiplies_the_base_stat() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.STR: 10})
	var weapon := EquipmentDef.new()
	weapon.slot = EquipmentDef.Slot.MAIN_HAND
	weapon.attribute_percent = {CG.Attribute.STR: 0.20}
	pawn.main_hand = weapon
	assert_almost_eq(pawn.effective_attribute(CG.Attribute.STR), 12.0, 0.001, "10 STR +20%% should be 12")


func test_armor_attribute_flat_adds_before_percent() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 10})
	var armor := EquipmentDef.new()
	armor.slot = EquipmentDef.Slot.BODY
	armor.attribute_flat = {CG.Attribute.CON: 3}
	armor.attribute_percent = {CG.Attribute.CON: 0.10}
	pawn.body = armor
	assert_almost_eq(pawn.effective_attribute(CG.Attribute.CON), 14.3, 0.001, "(10+3) * 1.10 = 14.3")


func test_equipped_weapon_raises_max_hp_through_str() -> void:
	var pawn := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.CON: 5, CG.Attribute.STR: 10})
	var bare_hp := pawn.max_hp()
	var weapon := EquipmentDef.new()
	weapon.slot = EquipmentDef.Slot.MAIN_HAND
	weapon.attribute_percent = {CG.Attribute.STR: 0.50}
	pawn.main_hand = weapon
	assert_true(pawn.max_hp() > bare_hp, "a weapon buffing STR should raise max hp through HP_PER_STR_BONUS")


func test_accessory_attribute_percent_raises_attack_power() -> void:
	var pawn := _pawn(CG.Method.MAGICAL, CG.Style.RANGED, {CG.Attribute.INT: 10})
	var bare := pawn.attack_power(CG.DamageType.FIRE)
	var accessory := EquipmentDef.new()
	accessory.slot = EquipmentDef.Slot.ACCESSORY
	accessory.attribute_percent = {CG.Attribute.INT: 0.30}
	pawn.accessory = accessory
	assert_true(pawn.attack_power(CG.DamageType.FIRE) > bare, "an accessory buffing INT should raise a Magical class's attack power")


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
	assert_almost_eq(pawn.effective_attribute(CG.Attribute.STR), 13.0, 0.001, "all three slots should stack their flat bonus")
