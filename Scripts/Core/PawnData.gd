extends Resource
class_name PawnData


## A pawn as it exists outside a fight: identity, class, equipment, plans. The
## simulation never mutates one of these. It reads it once when building the
## CombatUnit, so the same PawnData can be dropped into the same fight twice and
## produce the same fight twice.

@export var id: StringName = &""
@export var display_name: String = ""
@export var pawn_class: ClassDef

## Flat attribute bonuses from equipment and levels, keyed by CG.Attribute.
## Kept separate from the class spread so the source of a number stays visible
## when a fight reads wrong.
@export var attribute_bonus: Dictionary = {}

@export var weapon: EquipmentDef
@export var armor: EquipmentDef
@export var accessory: EquipmentDef

## Plans in priority order, highest first. Per README.md, when several plans
## would fire on the same tick exactly one fires: the earliest in this array.
@export var plans: Array[Plan] = []

func attribute(a: CG.Attribute) -> int:
	var base := 0
	if pawn_class != null:
		base = pawn_class.attribute(a)
	return base + int(attribute_bonus.get(a, 0))

func equipment() -> Array[EquipmentDef]:
	var out: Array[EquipmentDef] = []
	for e in [weapon, armor, accessory]:
		if e != null:
			out.append(e)
	return out
