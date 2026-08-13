extends RefCounted

const Registry := preload("res://Scripts/Content/Registry.gd")
const Balance := preload("res://Scripts/Content/Balance.gd")
const PlanInterpreter := preload("res://Scripts/Plans/PlanInterpreter.gd")
const DefaultBehavior := preload("res://Scripts/Plans/DefaultBehavior.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")

## Every place CombatSim needs a number or a lookup it does not own. Default
## values wire to the real content system (Balance, Registry); a test builds
## its own SimDeps with plain lambdas and drives the simulation with whatever
## numbers make the case clear, with no dependency on Balance, PlanInterpreter
## or a single piece of registered content.
##
## This is what keeps the promise in issue 1: CombatSim.gd itself contains no
## call to Balance and no hardcoded tuning number anywhere. The defaults below
## are the only bridge to Balance, and they live here, not in CombatSim.gd, so
## a reviewer can see the whole bridge in one place.

var enemy_lookup: Callable = Registry.get_enemy
var action_lookup: Callable = Registry.get_action

var max_hp: Callable = _default_max_hp
var max_resource: Callable = _default_max_resource
var move_speed: Callable = _default_move_speed

var attack_power: Callable = _default_attack_power
var damage_reduction: Callable = _default_damage_reduction
var wind_up_ticks: Callable = _default_wind_up_ticks
var recover_ticks: Callable = _default_recover_ticks

## Decision layer. Same reasoning: CombatSim.gd never names PlanInterpreter or
## DefaultBehavior directly, so a test can hand-write "attack nearest enemy"
## as a lambda and run a whole fight through CombatSim.run without either one
## implemented, and without depending on their stubs' behaviour (push_error
## and Intent.idle()) while they are still unbuilt.
var plan_decide: Callable = PlanInterpreter.decide
var default_decide: Callable = DefaultBehavior.decide

## Resource per tick, before the ceiling. Never consulted for a RAGE unit —
## CombatSim enforces that structurally rather than trusting every possible
## rate function to return 0 for it. No Balance function for a rate exists
## yet, so the default is 0: real numbers arrive the moment
## `Balance.resource_regen_per_tick(pawn, kind) -> float` exists and this
## default is updated to call it, the same one-line shape as every other
## default here.
var resource_regen_per_tick: Callable = _default_resource_regen_per_tick

## Resource gained the moment an attack actually lands (not on commit, not on
## a miss). Only consulted for a RAGE unit. Same pending-Balance-function note
## as above: `Balance.rage_gain_per_attack(pawn) -> float`.
var rage_gain_on_attack: Callable = _default_rage_gain_on_attack

static func _default_max_hp(pawn: PawnData) -> int:
	return Balance.max_hp(pawn)

static func _default_max_resource(pawn: PawnData) -> int:
	return Balance.max_resource(pawn)

static func _default_move_speed(pawn: PawnData) -> float:
	return Balance.move_speed(pawn)

## Enemies carry attack power directly on EnemyDef; they skip the attribute
## system per EnemyDef's own doc comment, so there is nothing for Balance to
## derive for them.
static func _default_attack_power(unit: CombatUnit, action: ActionDef) -> float:
	if unit.pawn != null:
		return Balance.attack_power(unit.pawn, action.damage_type) * action.power_scale
	var enemy_def: EnemyDef = Registry.get_enemy(unit.enemy_id)
	if enemy_def == null:
		return 0.0
	return float(enemy_def.attack_power.get(action.damage_type, 0)) * action.power_scale

static func _default_damage_reduction(unit: CombatUnit) -> float:
	if unit.pawn != null:
		return Balance.damage_reduction(unit)
	var enemy_def: EnemyDef = Registry.get_enemy(unit.enemy_id)
	if enemy_def == null:
		return 0.0
	return enemy_def.damage_reduction

static func _default_wind_up_ticks(unit: CombatUnit, action: ActionDef) -> int:
	if unit.pawn != null:
		return Balance.scale_action_ticks(action.wind_up_ticks, unit.pawn)
	return action.wind_up_ticks

static func _default_recover_ticks(unit: CombatUnit, action: ActionDef) -> int:
	if unit.pawn != null:
		return Balance.scale_action_ticks(action.recover_ticks, unit.pawn)
	return action.recover_ticks

## No Balance.resource_regen_per_tick exists yet. 0 keeps that honest instead
## of inventing a rate in Scripts/Combat/.
static func _default_resource_regen_per_tick(_unit: CombatUnit) -> float:
	return 0.0

## No Balance.rage_gain_per_attack exists yet. Same reasoning as above.
static func _default_rage_gain_on_attack(_unit: CombatUnit) -> float:
	return 0.0
