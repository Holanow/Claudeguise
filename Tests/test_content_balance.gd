extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Balance := preload("res://Scripts/Content/Balance.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")

## Balance formulas, tested against hand-built PawnData so this file needs
## nothing from CombatSim or Registry to run.

func _pawn(method: CG.Method, style: CG.Style, attrs: Dictionary) -> PawnData:
	var c := ClassDef.new()
	c.method = method
	c.style = style
	c.base_attributes = attrs
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


func test_plan_block_budget_tracks_wis() -> void:
	var low := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.WIS: 2})
	var high := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.WIS: 6})
	assert_eq(Balance.plan_block_budget(low), 2)
	assert_eq(Balance.plan_block_budget(high), 6)


func test_plan_block_budget_never_zero() -> void:
	var no_wis := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {})
	assert_true(Balance.plan_block_budget(no_wis) >= 1)


func test_scale_action_ticks_speeds_up_with_agi_and_has_a_floor() -> void:
	var slow := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 0})
	var fast := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 9999})
	assert_eq(Balance.scale_action_ticks(20, slow), 20)
	assert_eq(Balance.scale_action_ticks(20, fast), 10, "capped at MAX_AGI_TICK_SCALE = 0.5")


func test_scale_action_ticks_never_reaches_zero() -> void:
	var fast := _pawn(CG.Method.MARTIAL, CG.Style.MELEE, {CG.Attribute.AGI: 9999})
	assert_true(Balance.scale_action_ticks(1, fast) >= 1)
