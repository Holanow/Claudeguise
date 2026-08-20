extends Resource
class_name EquipmentDef


## Weapon, armor or accessory. All three share one shape and the slot decides
## which fields are read.

enum Slot { WEAPON, ARMOR, ACCESSORY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var slot: Slot = Slot.WEAPON

## What the player reads on the item. Write what it does to the pawn, not to the
## numbers: "Heavy, and slows you down" rather than "AGI -0.15".
@export var description: String = ""

## Percentage multipliers keyed by CG.Attribute. 0.10 is +10%.
@export var attribute_percent: Dictionary = {}

## Flat additions keyed by CG.Attribute.
@export var attribute_flat: Dictionary = {}

## Armor only. Fraction of incoming damage removed before it is applied.
@export var damage_reduction: float = 0.0

## ActionDef ids this piece grants its wielder.
@export var granted_actions: Array[StringName] = []

## Which `CG.Method` may wear or wield this. **Empty means anyone**, so adding
## this field invalidated no existing content. Declaring is Core's job and
## enforcing is not: the equip screen should never offer a piece a pawn cannot
## use, so the player meets this as an absence rather than an error.
@export var allowed_methods: Array[CG.Method] = []

## Here rather than in the equip screen or the registry, so every caller answers
## the question the same way.
func allows(pawn_method: CG.Method) -> bool:
	return allowed_methods.is_empty() or allowed_methods.has(pawn_method)
