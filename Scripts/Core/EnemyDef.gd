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

@export var actions: Array[StringName] = []

## Tags shown to the player above the health bar.
@export var display_tags: Array[String] = []

## Taunt radius applied when this unit is spawned as a summon. 0.0 means it does
## not taunt, which is every enemy today. It exists because a non-pawn unit's
## action list only ever runs one fixed action, so a siege engine could otherwise
## taunt forever or fight, never both. Read in `CombatSim._build_enemy_unit`.
@export var spawn_taunt_radius: float = 0.0

## How strongly this enemy prefers a target its allies already attack, 0.0 for
## nearest-and-ignore-everyone to 1.0 for always-join-the-pile.
@export var focus_bias: float = 0.0
