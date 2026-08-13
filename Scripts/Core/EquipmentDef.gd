extends Resource

const CG := preload("res://Scripts/Core/CG.gd")

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

## Which `CG.Method` may wear or wield this. **Empty means anyone**, which is
## what every item registered before this field existed keeps meaning, so adding
## it invalidates no content and no measurement.
##
## teal asked for this rather than guessing at it, having noticed nothing stops a
## caster wearing plate. It reuses `ClassDef.method`, the vocabulary the game
## already has, instead of inventing a parallel tag system beside it -- there is
## already `method`, `style`, `role_primary` and `role_secondary` on a class, and
## a second way of saying the same thing is how those two drift apart.
##
## Only `method` and not `style`, deliberately. Martial versus magical is the
## axis that makes a caster in plate wrong, and I would rather add `style` when
## an item actually needs it than ship two fields where one is exercised.
##
## **Declaring is Core's job; enforcing is not.** The equip screen should never
## offer a piece a pawn cannot use, so the player meets this as an absence rather
## than an error message. A content test should assert the declarations are
## coherent. Neither of those lives in this file.
@export var allowed_methods: Array[CG.Method] = []

## True when `pawn_method` may use this piece. Here rather than in the equip
## screen or the registry so that every caller answers the question the same way.
func allows(pawn_method: CG.Method) -> bool:
	return allowed_methods.is_empty() or allowed_methods.has(pawn_method)
