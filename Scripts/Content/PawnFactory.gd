extends RefCounted
class_name PawnFactory


## Builds a starter PawnData: class definition, preset plans, starting gear.

## The weapon each class starts holding. Every entry must satisfy
## `EquipmentDef.allows(class.method)` -- MARTIAL takes Sword and Bow, MAGICAL
## takes Sickle, Orb and Staff -- or the pawn is equipped with something the
## equip screen would refuse to offer it. There is a test for that.
const STARTING_WEAPON := {
	&"warrior": &"sword",
	&"priest": &"staff",
	&"geysermancer": &"orb",
	&"siege_master": &"bow",
	&"abomination": &"sickle",
}

## The armour a class starts wearing.
##
## **Issue 160: a starter pawn wearing nothing made every measurement tool in
## this repo blind to any armour-granted ability**, and there is exactly one of
## those -- `plate_mail` grants `warrior_block`. Issue 166 adds the two Mana
## casters for the same reason at one remove: the Robes carry the two points of
## WIS that pay for their Channel row.
const STARTING_ARMOR := {
	&"warrior": &"plate_mail",
	&"priest": &"robes",
	&"geysermancer": &"robes",
}

static func make_starter_pawn(class_id: StringName, pawn_id: StringName, display_name: String) -> PawnData:
	var pawn := PawnData.new()
	pawn.id = pawn_id
	pawn.display_name = display_name
	pawn.pawn_class = Registry.get_class_def(class_id)
	pawn.plans = PresetPlans.for_class(class_id)
	if STARTING_WEAPON.has(class_id):
		pawn.weapon = Registry.get_equipment(STARTING_WEAPON[class_id])
	if STARTING_ARMOR.has(class_id):
		pawn.armor = Registry.get_equipment(STARTING_ARMOR[class_id])
	return pawn
