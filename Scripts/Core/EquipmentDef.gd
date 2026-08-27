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

## Issue 632: shape changes this item makes to abilities it did not author.
## Empty on every item that ships today, so nothing changes until one is set.
@export var modifiers: Array[AbilityModifier] = []

## Armor only. Fraction of incoming damage removed before it is applied.
@export var damage_reduction: float = 0.0

## ActionDef ids this piece grants its wielder.
@export var granted_actions: Array[StringName] = []

## Every `CG.Tag` a class must carry to wear or wield this, all of them, not
## any. **Empty means anyone**, and more specialised gear names more tags --
## the player's own example is a kite shield at MARTIAL against a tower shield
## at MARTIAL and TANK. Issue 131; replaces `allowed_methods`, which could only
## express one axis.
@export var required_tags: Array[int] = []

## Here rather than in the equip screen or the registry, so every caller answers
## the question the same way.
func allows_class(class_def: ClassDef) -> bool:
	return missing_tags(class_def).is_empty()

## Which required tags this class does not carry, in declaration order. A caller
## that has to say *why* a piece is refused reads this; `allows_class` is the
## same question asked for a yes or no.
func missing_tags(class_def: ClassDef) -> Array[int]:
	if class_def == null:
		return []
	var have := class_def.tags()
	var out: Array[int] = []
	for t in required_tags:
		if not have.has(t):
			out.append(t)
	return out

## The method axis alone, for callers that hold a `CG.Method` and no class.
## Weaker than `allows_class` by exactly the tags it cannot see.
func allows(pawn_method: CG.Method) -> bool:
	var wanted: int = ClassDef.METHOD_TAG[pawn_method]
	for t in required_tags:
		if ClassDef.METHOD_TAG.values().has(t) and t != wanted:
			return false
	return true
