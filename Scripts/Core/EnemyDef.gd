extends Resource

const CG := preload("res://Scripts/Core/CG.gd")

## An enemy type. Per README.md enemies have visible health and tags and simple
## individual patterns, so they carry stats directly rather than deriving them
## through a class the way a pawn does.
##
## MANAGER-OWNED SHAPE. Instances live in Scripts/Content/Enemies/.

@export var id: StringName = &""
@export var display_name: String = ""

@export var hp_max: int = 10
@export var resource_max: int = 0
@export var resource_kind: CG.ResourceKind = CG.ResourceKind.ENERGY

## World units per tick.
@export var move_speed: float = 1.0
@export var radius: float = 12.0

## Flat attack power per damage type, keyed by CG.DamageType. Enemies skip the
## attribute system entirely; there is no pawn behind them to grow.
@export var attack_power: Dictionary = {}

@export var damage_reduction: float = 0.0

@export var actions: Array[StringName] = []

## Tags shown to the player above the health bar.
@export var display_tags: Array[String] = []
