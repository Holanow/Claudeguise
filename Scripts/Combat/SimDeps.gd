extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
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
## rate function to return 0 for it.
var resource_regen_per_tick: Callable = _default_resource_regen_per_tick

## Resource gained the moment an attack actually lands (not on commit, not on
## a miss). Only consulted for a RAGE unit.
var rage_gain_on_attack: Callable = _default_rage_gain_on_attack

## Issue 132. How many times the ordinary regeneration rate a unit recovers on
## a tick it spends idle -- neither moving nor acting. 1.0 means "no faster
## than any other tick", which is exactly the behaviour every fight measured
## before this existed.
##
## A multiplier on `resource_regen_per_tick` rather than a second rate, so a
## class that regenerates quickly also waits productively, and content has one
## number to reason about instead of two that can disagree about which pawn is
## patient.
##
## Like `slowed_speed_scale` before it, this does NOT call Balance:
## `Balance.idle_resource_regen_scale` does not exist, and a call to a Balance
## method that is not there is a **parse-time** failure in every script that
## transitively preloads this one, not a runtime failure where the feature is
## used. That was measured on this file once already. The content half is one
## line here the moment finch adds the function.
##
## The default is 1.0 rather than a placeholder number on purpose. This one is
## not merely "unwired": at any value above 1.0 it consumes a random number per
## idle tick through `_stochastic_round` and therefore moves every fight in the
## game. 1.0 returns before that happens, so the mechanism lands provably
## changing nothing, and the number that turns it on is a single deliberate
## content decision rather than a side effect of merging this.
var idle_resource_regen_scale: Callable = _default_idle_resource_regen_scale

## Damage-over-time per tick for a status a unit is carrying. `status` is
## always BURN or POISON in practice -- the seam takes any CG.Status rather
## than hardcoding those two, so a future DOT status needs no change here.
var status_damage_per_tick: Callable = _default_status_damage_per_tick

## Multiplier on wind-up/recover ticks for a unit carrying HASTE.
var haste_tick_scale: Callable = _default_haste_tick_scale

## Multiplier on move_speed for a unit carrying SLOWED. Same seam as
## haste_tick_scale, for the same reason: content owns the number, CombatSim
## only owns applying it.
##
## Unlike every other default here, this one does NOT call Balance: nothing
## has applied SLOWED yet (issue 14's content half -- the grapple magnitude
## and duration -- has not landed), and Balance.gd is not this file's to
## edit. `Balance.haste_tick_scale` already existing is exactly why
## _default_haste_tick_scale can call it safely; a call to a Balance method
## that does not exist is a **parse-time** error here, not a runtime one --
## GDScript resolves a static call on a preloaded const at analysis time, so
## it took down every script that (transitively) preloads this one, not just
## a test that exercises SLOWED. Measured, not assumed: that is exactly what
## happened on the first gate run of this file. _DEFAULT_SLOWED_SPEED_SCALE
## below is a local placeholder for exactly that reason, until content wires
## a real `Balance.slowed_speed_scale(unit) -> float` and this default is
## pointed at it in one line.
var slowed_speed_scale: Callable = _default_slowed_speed_scale

## Half speed. A placeholder, not a balance decision -- see the comment above.
const _DEFAULT_SLOWED_SPEED_SCALE := 0.5

static func _default_max_hp(pawn: PawnData) -> int:
	return Balance.max_hp(pawn)

static func _default_max_resource(pawn: PawnData) -> int:
	return Balance.max_resource(pawn)

static func _default_move_speed(pawn: PawnData) -> float:
	return Balance.move_speed(pawn)

## Enemies carry attack power directly on EnemyDef; they skip the attribute
## system per EnemyDef's own doc comment, so there is nothing for Balance to
## derive for them.
## `rng` is the fight's seeded generator, handed down so Balance can vary a
## pawn's damage with it. Optional, so a test can call this with two
## arguments and get the old deterministic behaviour.
##
## Enemies do not get it: their attack power is a flat number on EnemyDef,
## and a spread on that would put balance in a second, invisible place.
static func _default_attack_power(unit: CombatUnit, action: ActionDef, rng: RandomNumberGenerator = null) -> float:
	if unit.pawn != null:
		return Balance.attack_power(unit.pawn, action.damage_type, rng) * action.power_scale
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

static func _default_resource_regen_per_tick(unit: CombatUnit) -> float:
	return Balance.resource_regen_per_tick(unit)

static func _default_rage_gain_on_attack(unit: CombatUnit) -> float:
	return Balance.rage_gain_per_attack(unit)

static func _default_status_damage_per_tick(unit: CombatUnit, status: CG.Status) -> float:
	return Balance.status_damage_per_tick(unit, status)

static func _default_haste_tick_scale(unit: CombatUnit) -> float:
	return Balance.haste_tick_scale(unit)

static func _default_slowed_speed_scale(_unit: CombatUnit) -> float:
	return _DEFAULT_SLOWED_SPEED_SCALE

## 1.0 is "idling recovers no faster than any other tick", which is what every
## fight in this project has always done. See the field's own comment above for
## why this default is not a placeholder in the way _DEFAULT_SLOWED_SPEED_SCALE
## is one.
static func _default_idle_resource_regen_scale(_unit: CombatUnit) -> float:
	return 1.0
