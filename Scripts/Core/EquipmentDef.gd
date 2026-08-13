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

## One or two sentences a player reads on the item, in their language rather
## than ours. Same field and same reason as `ActionDef.description`: the player
## asked to be able to look at a thing and understand what it does before
## committing to it, and an item that silently edits an attribute is exactly the
## kind of change that is invisible in a fight.
##
## Write what it does to the pawn, not what it does to the numbers. "Heavy, and
## slows you down" rather than "AGI -0.15".
@export var description: String = ""

## Percentage multipliers keyed by CG.Attribute. 0.10 is +10%.
@export var attribute_percent: Dictionary = {}

## Flat additions keyed by CG.Attribute.
@export var attribute_flat: Dictionary = {}

## Armor only. Fraction of incoming damage removed before it is applied.
@export var damage_reduction: float = 0.0

## ActionDef ids this piece grants its wielder.
@export var granted_actions: Array[StringName] = []
