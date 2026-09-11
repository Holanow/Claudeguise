extends Resource
class_name AffixDef

## Issue 916: one rollable property an item may gain when it is generated. The
## item itself is authored; the affix and its value are not.

## README's two halves. NUMBERS are invisible arithmetic and floor 1 rolls only
## these; VERBS change what a pawn does and unlock deeper.
enum Kind { NUMBER, VERB }

## The player's four floor 1 kinds, 2026-09-10: attribute boosts, +life,
## damage reduction and % increased damage. Issue 931 appends README's four
## verbs below them; appended rather than filed beside their kin because these
## are ordinals and an authored `.tres` stores the number.
enum Effect {
	ATTRIBUTE_FLAT,
	MAX_HP_FLAT,
	DAMAGE_REDUCTION,
	DAMAGE_PERCENT,
	## Issue 931: a share of the damage a hit landed, returned to the attacker.
	LIFE_LEECH,
	## Issue 931: a share taken off every cooldown, the same seam the Book uses.
	COOLDOWN_RECOVERY,
	## Issue 931: a share of the killer's own pool, granted when it kills.
	RESOURCE_ON_KILL,
	## Issue 931: a chance to apply `status` for `status_ticks` on a landed hit.
	ON_HIT_STATUS,
}

## Which effects change what a pawn DOES. `kind` is authored beside this and
## `test_content_affixes` holds the two together.
const VERB_EFFECTS: Array[Effect] = [
	Effect.LIFE_LEECH, Effect.COOLDOWN_RECOVERY, Effect.RESOURCE_ON_KILL,
	Effect.ON_HIT_STATUS,
]

@export var id: StringName = &""

## What the player reads. One word, so a rolled item's own name stays short.
@export var display_name: String = ""

@export var kind: Kind = Kind.NUMBER
@export var effect: Effect = Effect.ATTRIBUTE_FLAT

## Read only by ATTRIBUTE_FLAT; every other effect ignores it.
@export var attribute: CG.Attribute = CG.Attribute.STR

## Read only by ON_HIT_STATUS: what it applies and for how long. The rolled
## value is the chance, so the duration is authored rather than drawn.
@export var status: CG.Status = CG.Status.BLEED
@export var status_ticks: int = 0

## The ACCESSORY-slot range, inclusive. Every other slot scales it by
## `AffixPools.SLOT_SCALE`, which is what makes a body beat a ring.
@export var base_min: float = 0.0
@export var base_max: float = 0.0

## A fraction is drawn in hundredths so the value is an exact two-decimal
## number rather than wherever a float range happened to land. Every verb is a
## rate, a share or a chance, so only the two flat number effects are whole.
func is_fraction() -> bool:
	return effect != Effect.ATTRIBUTE_FLAT and effect != Effect.MAX_HP_FLAT

static func is_verb_effect(e: Effect) -> bool:
	return VERB_EFFECTS.has(e)
