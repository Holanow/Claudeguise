extends Resource

## Weapon, armor or accessory. README.md gives each slot a different way of
## changing a pawn, so all three are kept on one shape and the slot decides
## which fields are read.
##
## MANAGER-OWNED SHAPE. Instances belong to the content session.

enum Slot { WEAPON, ARMOR, ACCESSORY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var slot: Slot = Slot.WEAPON

## Percentage multipliers keyed by CG.Attribute. 0.10 is +10%.
@export var attribute_percent: Dictionary = {}

## Flat additions keyed by CG.Attribute.
@export var attribute_flat: Dictionary = {}

## Armor only. Fraction of incoming damage removed before it is applied.
@export var damage_reduction: float = 0.0

## ActionDef ids this piece grants its wielder.
@export var granted_actions: Array[StringName] = []
