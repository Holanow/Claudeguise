extends RefCounted

const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PresetPlans := preload("res://Scripts/Content/PresetPlans.gd")

## Builds a starter PawnData for a class: the class definition, its two preset
## plans, and a starting weapon. No armor, no accessory, no attribute bonuses --
## a class's own attribute spread is still what issue 2 balanced. Equipment
## generation past this one starting weapon is out of scope for this slice; see
## issue 41.
##
## Not part of the Registry module contract (Registry composes content
## definitions, not live pawn instances), but lives under Scripts/Content/
## because it is content, and both this issue's tests and whatever builds the
## party-select roster need it.
##
## OWNER: teal.

## Issue 41: the smallest proof that the item chain (registry -> item -> pawn
## slot -> Balance.attribute -> attack power -> a fight outcome) actually
## runs end to end, rather than sitting fully wired and never exercised the
## way EquipmentDef itself did all night. One weapon per class, each legal
## for that class's own method per EquipmentDef.allowed_methods -- picked by
## hand rather than by a generator, since a starter class's kit is content
## the same way its actions are, not a roll.
const STARTING_WEAPON: Dictionary = {
	&"warrior": &"sword",
	&"siege_master": &"wrench",
	&"abomination": &"sickle",
	&"priest": &"orb",
	&"geysermancer": &"orb",
}

static func make_starter_pawn(class_id: StringName, pawn_id: StringName, display_name: String) -> PawnData:
	var pawn := PawnData.new()
	pawn.id = pawn_id
	pawn.display_name = display_name
	pawn.pawn_class = Registry.get_class_def(class_id)
	pawn.plans = PresetPlans.for_class(class_id)
	var weapon_id: StringName = STARTING_WEAPON.get(class_id, &"")
	if weapon_id != &"":
		pawn.weapon = Registry.get_equipment(weapon_id)
	return pawn
