extends Resource
class_name PawnData


## A pawn as it exists outside a fight: identity, class, equipment, plans. The
## simulation never mutates one of these. It reads it once when building the
## CombatUnit, so the same PawnData can be dropped into the same fight twice and
## produce the same fight twice.

@export var id: StringName = &""
@export var display_name: String = ""
@export var pawn_class: ClassDef

## Flat attribute bonuses from equipment and levels, keyed by CG.Attribute.
## Kept separate from the class spread so the source of a number stays visible
## when a fight reads wrong.
@export var attribute_bonus: Dictionary = {}

@export var main_hand: EquipmentDef
@export var off_hand: EquipmentDef
@export var head: EquipmentDef
@export var body: EquipmentDef
@export var accessory: EquipmentDef

## Plans in priority order, highest first. Per README.md, when several plans
## would fire on the same tick exactly one fires: the earliest in this array.
## `CombatSim` reads this and only this; a running fight must never see it
## change mid-fight, so an edit made while a fight is live goes to
## `staged_plans` instead and is committed here by `FloorRun.carry_into`.
@export var plans: Array[Plan] = []

## `true` once a staged clone of `plans` exists for the fight in progress.
## Opening the editor mid-fight sets this; it says nothing about whether the
## player has actually changed anything yet -- see `plans_edited` for that.
@export var plans_staged: bool = false
@export var staged_plans: Array[Plan] = []

## `true` once the player has actually changed a staged row, as opposed to
## merely opening the editor while a fight runs. The verdict column and the
## "takes effect next room" note key off this, not off `plans_staged`: a
## player who opened the panel and changed nothing must see the same real
## verdicts they would see with the panel closed.
@export var plans_edited: bool = false

## Issue 755: standing preferences a plan row's own block overrides. Read by
## `UnitGlobals`, and only by `DefaultBehavior`/`CombatSim` -- a row that
## already carries its own targeting or movement block never consults these,
## which is what "the global is a default, never an override" means.
##
## `_avoid_hazard` has run on every `MOVE_TO` unconditionally since #163; this
## is what makes the opposite choice possible for the first time, and every
## pawn defaults to the behaviour that already shipped.
@export var avoid_hazards: bool = true

## `""` (default) is nearest, matching `DefaultBehavior`'s own baseline before
## this issue. `UnitGlobals.TARGET_FARTHEST` is the only other value today.
@export var target_preference: StringName = &""

## `UnitGlobals.POSTURE_SEEK_ENEMY` (default, today's behaviour) or
## `UnitGlobals.POSTURE_STAND_NEAR_ALLY`.
@export var posture: StringName = &"seek_enemy"

## The named ally's `PawnData.id`, read only when `posture` is
## `stand_near_ally`. A dead ally, a dangling id, or naming oneself all
## degrade to `seek_enemy` -- see `UnitGlobals.stand_near_ally_unit`.
@export var stand_near_ally_id: StringName = &""

func attribute(a: CG.Attribute) -> int:
	var base := 0
	if pawn_class != null:
		base = pawn_class.attribute(a)
	return base + int(attribute_bonus.get(a, 0))

func equipment() -> Array[EquipmentDef]:
	var out: Array[EquipmentDef] = []
	for e in [main_hand, off_hand, head, body, accessory]:
		if e != null:
			out.append(e)
	return out


## Issue 770: every number derived from this pawn's attributes, next to the
## attributes it derives from. Was `Balance.gd`.

const BASE_HP := 60
const HP_PER_CON := 12
const HP_PER_STR_BONUS := 2

const BASE_RESOURCE := 30
const RESOURCE_PER_ATN := 8
const RESOURCE_PER_INT_BONUS := 2

## World units per tick.
const BASE_MOVE_SPEED := 3.0
const MOVE_PER_AGI := 0.4
const MOVE_PER_DEX_BONUS := 0.05

## Issue 491: 1.9 x the mean starting-weapon grant. Every pawn has always held
## a weapon, so a class's real damage was always its base times that multiplier;
## #489 removed the multiplier and revealed that the base was never the whole
## number. The five grants were sword STR 15%, staff INT 12%, orb INT 18%, bow
## DEX 15% and sickle INT 15%, and their mean is exactly 15%.
const ATTACK_POWER_PER_POINT := 2.185

## Issue 7: a hit rolls within [1 - spread, 1 + spread] of its base power.
const ATTACK_VARIANCE_SPREAD := 0.55

const DAMAGE_REDUCTION_PER_CON := 0.01
const NATURAL_DAMAGE_REDUCTION_CAP := 0.9

## Fraction shaved off an action's ticks per point of AGI. Issue 592 raised the
## cap to 0.9; `scale_action_ticks` floors the resolved count at one tick, so
## nothing here can take an action to zero.
const AGI_TICK_SCALE_PER_POINT := 0.015
const MAX_AGI_TICK_SCALE := 0.9

## Issue 790: how many plan rows a pawn may carry, flat for every pawn. WIS
## used to gate this and is gone; a class differs by what it can do, not by how
## much it is allowed to say.
const PLAN_ROW_CAP := 10

## Issue 39: `attribute` above plus equipment's `attribute_flat` and
## `attribute_percent`, which is what everything below derives from.
func effective_attribute(a: CG.Attribute) -> float:
	var value := float(attribute(a))
	var flat := 0.0
	var percent := 0.0
	for e in equipment():
		flat += e.total_attribute_flat(a)
		percent += float(e.attribute_percent.get(a, 0.0))
	return (value + flat) * (1.0 + percent)

func max_hp() -> int:
	var str_bonus := effective_attribute(CG.Attribute.STR)
	return int(round(BASE_HP + effective_attribute(CG.Attribute.CON) * HP_PER_CON + str_bonus * HP_PER_STR_BONUS + gear_max_hp_flat()))

func max_resource() -> int:
	var int_bonus := effective_attribute(CG.Attribute.INT)
	return int(round(BASE_RESOURCE + effective_attribute(CG.Attribute.ATN) * RESOURCE_PER_ATN + int_bonus * RESOURCE_PER_INT_BONUS))

## World units per tick.
func move_speed() -> float:
	var dex_bonus := effective_attribute(CG.Attribute.DEX)
	return BASE_MOVE_SPEED + effective_attribute(CG.Attribute.AGI) * MOVE_PER_AGI + dex_bonus * MOVE_PER_DEX_BONUS

## Attack power for one damage type, before the action's own power_scale.
func attack_power(d: CG.DamageType, rng: RandomNumberGenerator = null) -> float:
	var _unused := d
	if pawn_class == null:
		return 0.0
	var attr := CG.Attribute.STR
	if pawn_class.method == CG.Method.MAGICAL:
		attr = CG.Attribute.INT
	elif pawn_class.style == CG.Style.MELEE:
		attr = CG.Attribute.STR
	else:
		attr = CG.Attribute.DEX
	var base := effective_attribute(attr) * ATTACK_POWER_PER_POINT
	if rng == null:
		return base
	return base * rng.randf_range(1.0 - ATTACK_VARIANCE_SPREAD, 1.0 + ATTACK_VARIANCE_SPREAD)

## Issue 916: flat maximum health rolled onto gear, summed across every piece.
func gear_max_hp_flat() -> float:
	var out := 0.0
	for e in equipment():
		out += e.affix_max_hp_flat()
	return out

## Issue 746: the best `damage_reduction` across every equipped item, not just
## `body`. A shield in `off_hand` carries the same field body armor always has,
## so a single-slot read stops seeing it. Best rather than summed: two items
## both reducing damage is not twice the protection.
func gear_damage_reduction() -> float:
	var best := 0.0
	for e in equipment():
		best = maxf(best, e.total_damage_reduction())
	return best

## Fraction of incoming damage this pawn's own toughness removes, before gear
## and before any status.
func natural_damage_reduction() -> float:
	return clampf(effective_attribute(CG.Attribute.CON) * DAMAGE_REDUCTION_PER_CON, 0.0, NATURAL_DAMAGE_REDUCTION_CAP)

## Ticks a wind-up or recovery takes after AGI is applied. Kept as a modifier on
## the action's own numbers so that "this action is slow" and "this pawn is
## slow" stay separately readable.
func scale_action_ticks(base_ticks: int) -> int:
	if base_ticks <= 0:
		return base_ticks
	var scale := clampf(effective_attribute(CG.Attribute.AGI) * AGI_TICK_SCALE_PER_POINT, 0.0, MAX_AGI_TICK_SCALE)
	return maxi(1, int(round(float(base_ticks) * (1.0 - scale))))
