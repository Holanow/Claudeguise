extends Resource

const CG := preload("res://Scripts/Core/CG.gd")

## A pawn class: a bag of tags, a base attribute spread, a resource kind and a
## set of starting actions. Per README.md a class never changes after the pawn
## is generated.
##
## MANAGER-OWNED SHAPE. The fields are frozen. The *instances* live in
## Scripts/Content/Classes/ and belong to the content session.

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
