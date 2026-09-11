extends Resource
class_name AffixDef

## Issue 916: one rollable property an item may gain when it is generated. The
## item itself is authored; the affix and its value are not.

## README's two halves. NUMBERS are invisible arithmetic and floor 1 rolls only
## these; VERBS change what a pawn does and unlock deeper.
enum Kind { NUMBER, VERB }

## The player's four floor 1 kinds, 2026-09-10: attribute boosts, +life,
## damage reduction and % increased damage.
enum Effect { ATTRIBUTE_FLAT, MAX_HP_FLAT, DAMAGE_REDUCTION, DAMAGE_PERCENT }

@export var id: StringName = &""

## What the player reads. One word, so a rolled item's own name stays short.
@export var display_name: String = ""

@export var kind: Kind = Kind.NUMBER
@export var effect: Effect = Effect.ATTRIBUTE_FLAT

## Read only by ATTRIBUTE_FLAT; every other effect ignores it.
@export var attribute: CG.Attribute = CG.Attribute.STR

## The ACCESSORY-slot range, inclusive. Every other slot scales it by
## `AffixPools.SLOT_SCALE`, which is what makes a body beat a ring.
@export var base_min: float = 0.0
@export var base_max: float = 0.0

## A fraction is drawn in hundredths so the value is an exact two-decimal
## number rather than wherever a float range happened to land.
func is_fraction() -> bool:
	return effect == Effect.DAMAGE_REDUCTION or effect == Effect.DAMAGE_PERCENT
