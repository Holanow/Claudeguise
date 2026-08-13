extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")

## Every tuning number in the game and every formula that turns attributes into
## the values the simulation uses.
##
## OWNER: teal.
##
## This file exists as a separate thing on purpose. The question this slice
## answers is whether the combat is fun, and answering it means changing numbers
## and re-running the same fight. If the numbers are spread through the
## simulation then every tuning pass is a diff in wren's files and a merge
## conflict. Here it is one file, one owner, one place to look.
##
## The simulation calls these. It must never hardcode a number that belongs
## here, and a reviewer should reject one that does.

const BASE_HP := 40
const HP_PER_CON := 9
const HP_PER_STR_BONUS := 2

const BASE_RESOURCE := 30
const RESOURCE_PER_ATN := 8
const RESOURCE_PER_INT_BONUS := 2

## World units per tick.
const BASE_MOVE_SPEED := 3.0
const MOVE_PER_AGI := 0.4
const MOVE_PER_DEX_BONUS := 0.05

const ATTACK_POWER_PER_POINT := 2.5

const DAMAGE_REDUCTION_PER_CON := 0.01
const NATURAL_DAMAGE_REDUCTION_CAP := 0.3
const STATUS_SHIELD_REDUCTION := 0.25
const STATUS_BLOCK_REDUCTION := 0.25
const MAX_DAMAGE_REDUCTION := 0.85

## Fraction shaved off an action's ticks per point of AGI, capped so a very
## fast pawn still takes at least half the base time.
const AGI_TICK_SCALE_PER_POINT := 0.015
const MAX_AGI_TICK_SCALE := 0.5

static func max_hp(pawn: PawnData) -> int:
	var str_bonus := pawn.attribute(CG.Attribute.STR)
	return BASE_HP + pawn.attribute(CG.Attribute.CON) * HP_PER_CON + str_bonus * HP_PER_STR_BONUS

static func max_resource(pawn: PawnData) -> int:
	var int_bonus := pawn.attribute(CG.Attribute.INT)
	return BASE_RESOURCE + pawn.attribute(CG.Attribute.ATN) * RESOURCE_PER_ATN + int_bonus * RESOURCE_PER_INT_BONUS

## World units per tick.
static func move_speed(pawn: PawnData) -> float:
	var dex_bonus := float(pawn.attribute(CG.Attribute.DEX))
	return BASE_MOVE_SPEED + float(pawn.attribute(CG.Attribute.AGI)) * MOVE_PER_AGI + dex_bonus * MOVE_PER_DEX_BONUS

## Attack power for one damage type, before the action's own power_scale.
##
## Per README.md: Martial+Melee scales off STR, Martial+Ranged (and
## Martial+Summoner, which has no dedicated attribute) scales off DEX, and any
## Magical class scales off INT regardless of style. `d` is accepted for the
## call shape SimDeps expects; the driving attribute for this slice comes from
## the class's method and style, not from the damage type of the action fired.
static func attack_power(pawn: PawnData, d: CG.DamageType) -> float:
	var _unused := d
	if pawn.pawn_class == null:
		return 0.0
	var attr := CG.Attribute.STR
	if pawn.pawn_class.method == CG.Method.MAGICAL:
		attr = CG.Attribute.INT
	elif pawn.pawn_class.style == CG.Style.MELEE:
		attr = CG.Attribute.STR
	else:
		attr = CG.Attribute.DEX
	return float(pawn.attribute(attr)) * ATTACK_POWER_PER_POINT

## Fraction of incoming damage removed, from armor and statuses. The simulation
## applies this; it does not decide it.
static func damage_reduction(unit: CombatUnit) -> float:
	if unit.pawn == null:
		return 0.0
	var reduction := clampf(float(unit.pawn.attribute(CG.Attribute.CON)) * DAMAGE_REDUCTION_PER_CON, 0.0, NATURAL_DAMAGE_REDUCTION_CAP)
	if unit.pawn.armor != null:
		reduction += unit.pawn.armor.damage_reduction
	if unit.has_status(CG.Status.SHIELD):
		reduction += STATUS_SHIELD_REDUCTION
	if unit.has_status(CG.Status.BLOCK):
		reduction += STATUS_BLOCK_REDUCTION
	return clampf(reduction, 0.0, MAX_DAMAGE_REDUCTION)

## How many blocks a pawn's plans may total, from WIS per README.md.
static func plan_block_budget(pawn: PawnData) -> int:
	return maxi(1, pawn.attribute(CG.Attribute.WIS))

## Ticks a wind-up or recovery takes after AGI is applied. Kept as a modifier on
## the action's own numbers so that "this action is slow" and "this pawn is
## slow" stay separately readable.
static func scale_action_ticks(base_ticks: int, pawn: PawnData) -> int:
	if base_ticks <= 0:
		return base_ticks
	var scale := clampf(float(pawn.attribute(CG.Attribute.AGI)) * AGI_TICK_SCALE_PER_POINT, 0.0, MAX_AGI_TICK_SCALE)
	return maxi(1, int(round(float(base_ticks) * (1.0 - scale))))
