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
