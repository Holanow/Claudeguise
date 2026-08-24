extends Resource
class_name EnemyDef


## An enemy type. Enemies carry stats directly rather than deriving them through
## a class the way a pawn does.

@export var id: StringName = &""
@export var display_name: String = ""

@export var hp_max: int = 10
@export var resource_max: int = 0
@export var resource_kind: CG.ResourceKind = CG.ResourceKind.ENERGY

## World units per tick.
@export var move_speed: float = 1.0

## **NOT drawing only**, whatever `CombatUnit.radius` implies.
## `CombatSim._move_toward` uses it for movement collision and a projectile's
## hit check uses the target's radius. Changing it changes fights.
@export var radius: float = 22.0

## Flat attack power per damage type, keyed by CG.DamageType. Enemies skip the
## attribute system; there is no pawn behind them to grow.
@export var attack_power: Dictionary = {}

@export var damage_reduction: float = 0.0

## Issue 542. Multiplier on how fast this enemy gets through an action's
## authored wind-up and recovery; 1.0 is exactly as authored, above 1.0 is
## faster. A pawn gets the same thing from AGI and an enemy had nothing.
@export var action_speed: float = 1.0

@export var actions: Array[StringName] = []

## Tags shown to the player above the health bar.
@export var display_tags: Array[String] = []

## How strongly this enemy prefers a target its allies already attack, 0.0 for
## nearest-and-ignore-everyone to 1.0 for always-join-the-pile.
@export var focus_bias: float = 0.0
