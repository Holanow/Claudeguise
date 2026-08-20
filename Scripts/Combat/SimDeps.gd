extends RefCounted
class_name SimDeps


## Every place CombatSim needs a number or a lookup it does not own. Default
## values wire to the real content system (Balance, Registry); a test builds
## its own SimDeps with plain lambdas and drives the simulation with whatever

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

## Which attack a unit falls back to on one side of the melee/ranged split.
## `(actions: Array[ActionDef], want_ranged: bool) -> ActionDef`.
var default_attack_action: Callable = DefaultBehavior.default_attack_action

## What a pawn's pool opens at, given its kind and its maximum. Issue 164.
##
## Pawns only -- `_build_enemy_unit` still opens every enemy at full, which is
## rook's ruling rather than an oversight: the player's direction was about mana
## classes, and moving the enemy line because it looks the same would be a
## balance change nobody asked for.
var starting_resource: Callable = Balance.starting_resource

## Resource per tick, before the ceiling. Never consulted for a RAGE unit Ã¢â‚¬â€
## CombatSim enforces that structurally rather than trusting every possible
## rate function to return 0 for it.
var resource_regen_per_tick: Callable = _default_resource_regen_per_tick

## Resource gained the moment an attack actually lands (not on commit, not on
## a miss). Only consulted for a RAGE unit.
var rage_gain_on_attack: Callable = _default_rage_gain_on_attack

## Issue 174. Rage gained by the VICTIM of a landed hit, given the unit and the
## damage that actually got through. Only consulted for a RAGE unit.
var rage_gain_on_damage_taken: Callable = _default_rage_gain_on_damage_taken

## Issue 132. How many times the ordinary regeneration rate a unit recovers on
## a tick it spends idle -- neither moving nor acting. 1.0 means "no faster
## than any other tick", which is exactly the behaviour every fight measured
var idle_resource_regen_scale: Callable = _default_idle_resource_regen_scale

## Damage-over-time per tick for a status a unit is carrying. `status` is
## always BURN or POISON in practice -- the seam takes any CG.Status rather
## than hardcoding those two, so a future DOT status needs no change here.
var status_damage_per_tick: Callable = _default_status_damage_per_tick

## Damage per tick contributed by each unit of a status's stored magnitude, ON
## TOP of `status_damage_per_tick` above. The whole rate is
var status_damage_per_magnitude: Callable = _default_status_damage_per_magnitude

## How many ticks apart a damage-over-time status deals its damage. 1 is every
## tick, which is what BURN and POISON have always done.
var status_tick_interval: Callable = _default_status_tick_interval

## How long a stacking status holds on after its expiry, per stack still left.
##
## `CombatSim._tick_statuses` drops ONE stack on expiry and re-arms for this
var status_stack_decay_ticks: Callable = _default_status_stack_decay_ticks

## Multiplier on wind-up/recover ticks for a unit carrying HASTE.
var haste_tick_scale: Callable = _default_haste_tick_scale

## Multiplier on move_speed for a unit carrying SLOWED. Same seam as
## haste_tick_scale, for the same reason: content owns the number, CombatSim
## only owns applying it.
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

## Percent of the victim's own max Rage per point of damage taken, so a big hit
## pays more than a small one and a large pool does not fill faster than a small
## one for the same beating.
##
## The number is measured, not guessed -- the sweep is in the pull request for
## issue 174. It is a placeholder only in the sense that it lives here rather
## than in `Balance`; the value is the one that made the class work.
const _RAGE_PERCENT_PER_DAMAGE_TAKEN := 0.9

static func _default_rage_gain_on_damage_taken(unit: CombatUnit, damage: int) -> float:
	return float(unit.resource_max) * (_RAGE_PERCENT_PER_DAMAGE_TAKEN / 100.0) * float(damage)

static func _default_status_damage_per_tick(unit: CombatUnit, status: CG.Status) -> float:
	return Balance.status_damage_per_tick(unit, status)

## BLEED'S PLACEHOLDER NUMBERS, and why they are here rather than in Balance.
##
## The stacking mechanism landed on top of an effect with no base: BLEED is in
const _BLEED_DAMAGE_PER_STACK_PER_TICK := 1.0

## Every 5 ticks, a third of a second. The player's *"does damage less often"*,
## against POISON's every single tick -- a rhythm a player can tell apart
## without reading a number.
const _BLEED_TICK_INTERVAL := 5

## Two seconds per stack. What makes a bleed read down 3, 2, 1 rather than
## vanishing whole the tick the thing applying it dies.
const _BLEED_STACK_DECAY_TICKS := 30

## Issue 121, finch: repointed at `Balance`, which is what the note above says to
## do once the method exists. It did not when swift wrote this -- "a call to a
## Balance method that does not exist is a parse-time failure" -- and that was an
static func _default_status_damage_per_magnitude(unit: CombatUnit, status: CG.Status) -> float:
	return Balance.status_damage_per_magnitude(unit, status)

static func _default_status_tick_interval(status: CG.Status) -> int:
	if status == CG.Status.BLEED:
		return _BLEED_TICK_INTERVAL
	return 1

static func _default_status_stack_decay_ticks(status: CG.Status) -> int:
	if status == CG.Status.BLEED:
		return _BLEED_STACK_DECAY_TICKS
	return 0

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
