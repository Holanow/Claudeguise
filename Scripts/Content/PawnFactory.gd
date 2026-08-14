extends RefCounted

const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PresetPlans := preload("res://Scripts/Content/PresetPlans.gd")

## Builds a starter PawnData for a class: the class definition, its preset
## plans, and the weapon its class fights with. Armour, accessories and loot
## generation are still out of scope for this slice, so this is the only way a
## fightable pawn gets made right now.
##
## Not part of the Registry module contract (Registry composes content
## definitions, not live pawn instances), but lives under Scripts/Content/
## because it is content, and both this issue's tests and whatever builds the
## party-select roster need it.
##
## OWNER: teal.
##
## **Issue 129: a starter pawn is armed, and until this issue it never was.**
## The player asked for both halves in the same breath -- "a unit's basic attack
## should be determined by its main hand weapon rather than its class" and "we
## should have a basic weapon and maybe offhand for the pawns at the start" --
## and the first is a pawn that cannot attack without the second. Every
## measurement this project has ever taken was on pawns wearing nothing (see the
## board); this is the change that ends that, and it moves numbers twice over:
## the attack now arrives from an item, and the item's own percentage applies.
##
## **An empty main hand means no basic attack. That is the shipped answer and it
## was chosen, not discovered.** The alternative was an implicit unarmed strike
## every pawn carries. Against it:
##
##   - It makes the weapon slot free. If bare hands always work, taking the
##     Sword off costs a percentage and nothing else, and the issue's whole
##     point -- the weapon decides how you fight -- goes with it.
##   - It could not be made honest today. `CombatSim._collect_player_actions`
##     still computes its own copy of the class-plus-equipment union instead of
##     calling `Registry.actions_for_pawn`, so a grant injected in the Registry
##     would appear in the plan editor and never in a fight. Shipping half of
##     that is the exact defect issue 100 found and fixed once already.
##
## What an unarmed pawn actually does is therefore class-specific and worth
## knowing: a Priest still smites and heals, a Geysermancer still blasts, a
## Siege Master still marks and builds, all at resource cost until the pool runs
## dry. A Warrior and an Abomination both stop, because Rage only refills from
## landed hits and neither has a way left to land one. Every starter is armed,
## so a player reaches that state only by deliberately emptying the slot on the
## equip screen, where the absence is on the screen in front of them.
##
## No offhand. `EquipmentDef.Slot` has WEAPON, ARMOR and ACCESSORY and no fourth
## slot; inventing one is a Core change and a bigger design question than this
## issue asked.

## The weapon each class starts holding. One per class, chosen so the pawn keeps
## exactly the basic attack it had before issue 129 -- a Warrior still Strikes,
## a Priest still Bolts -- so that the balance movement this change causes is
## attributable to the weapon's percentages and not to five new actions.
##
## Every entry satisfies `EquipmentDef.allows(class.method)`: MARTIAL classes
## take the Sword and the Bow, MAGICAL classes the Sickle, Orb and Staff. There
## is a test for that, because a mismatch here would equip a pawn with something
## the equip screen would refuse to offer it.
const STARTING_WEAPON := {
	&"warrior": &"sword",
	&"priest": &"staff",
	&"geysermancer": &"orb",
	&"siege_master": &"bow",
	&"abomination": &"sickle",
}

static func make_starter_pawn(class_id: StringName, pawn_id: StringName, display_name: String) -> PawnData:
	var pawn := PawnData.new()
	pawn.id = pawn_id
	pawn.display_name = display_name
	pawn.pawn_class = Registry.get_class_def(class_id)
	pawn.plans = PresetPlans.for_class(class_id)
	if STARTING_WEAPON.has(class_id):
		pawn.weapon = Registry.get_equipment(STARTING_WEAPON[class_id])
	return pawn
