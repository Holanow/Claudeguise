extends Resource
class_name ClassDef


## A pawn class: a bag of tags, a base attribute spread, a resource kind and a
## set of starting actions. Per README.md a class never changes after the pawn
## is generated.

@export var id: StringName = &""
@export var display_name: String = ""

@export var method: CG.Method = CG.Method.MARTIAL
@export var style: CG.Style = CG.Style.MELEE
@export var role_primary: CG.Role = CG.Role.DPS
@export var role_secondary: CG.Role = CG.Role.DPS

## CG.DamageType values. A class has one or two per README.md. Typed as int
## because GDScript has no typed array of a cross-script enum.
@export var damage_types: Array[int] = []

@export var resource_kind: CG.ResourceKind = CG.ResourceKind.ENERGY

## Keyed by CG.Attribute. Base spread before equipment. Balance.gd turns these
## into the derived numbers the simulation uses.
@export var base_attributes: Dictionary = {}

## ActionDef ids this class starts with, in no particular order.
@export var starting_actions: Array[StringName] = []

func attribute(a: CG.Attribute) -> int:
	return int(base_attributes.get(a, 0))

## Issue 131: what this class counts as, for gear that gates on tags. Derived
## from the four fields above rather than authored, so a class cannot claim a
## tag its own method, style or roles do not give it.
const METHOD_TAG := {CG.Method.MARTIAL: CG.Tag.MARTIAL, CG.Method.MAGICAL: CG.Tag.MAGICAL}
const STYLE_TAG := {CG.Style.MELEE: CG.Tag.MELEE, CG.Style.RANGED: CG.Tag.RANGED, CG.Style.SUMMONER: CG.Tag.SUMMONER}
const ROLE_TAG := {
	CG.Role.DPS: CG.Tag.DPS,
	CG.Role.SUPPORT: CG.Tag.SUPPORT,
	CG.Role.ANTI_SUPPORT: CG.Tag.ANTI_SUPPORT,
	CG.Role.TANK: CG.Tag.TANK,
	CG.Role.HEALER: CG.Tag.HEALER,
}

func tags() -> Array[int]:
	var out: Array[int] = [METHOD_TAG[method], STYLE_TAG[style], ROLE_TAG[role_primary]]
	var secondary: int = ROLE_TAG[role_secondary]
	if not out.has(secondary):
		out.append(secondary)
	return out
