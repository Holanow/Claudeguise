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

static func max_hp(pawn: PawnData) -> int:
	push_error("Balance.max_hp is not implemented yet (issue 2, owner teal)")
	return 1

static func max_resource(pawn: PawnData) -> int:
	push_error("Balance.max_resource is not implemented yet (issue 2, owner teal)")
	return 0

## World units per tick.
static func move_speed(pawn: PawnData) -> float:
	push_error("Balance.move_speed is not implemented yet (issue 2, owner teal)")
	return 0.0

## Attack power for one damage type, before the action's own power_scale.
static func attack_power(pawn: PawnData, d: CG.DamageType) -> float:
	push_error("Balance.attack_power is not implemented yet (issue 2, owner teal)")
	return 0.0

## Fraction of incoming damage removed, from armor and statuses. The simulation
## applies this; it does not decide it.
static func damage_reduction(unit: CombatUnit) -> float:
	push_error("Balance.damage_reduction is not implemented yet (issue 2, owner teal)")
	return 0.0

## How many blocks a pawn's plans may total, from WIS per README.md.
static func plan_block_budget(pawn: PawnData) -> int:
	push_error("Balance.plan_block_budget is not implemented yet (issue 2, owner teal)")
	return 0

## Ticks a wind-up or recovery takes after AGI is applied. Kept as a modifier on
## the action's own numbers so that "this action is slow" and "this pawn is
## slow" stay separately readable.
static func scale_action_ticks(base_ticks: int, pawn: PawnData) -> int:
	push_error("Balance.scale_action_ticks is not implemented yet (issue 2, owner teal)")
	return base_ticks
