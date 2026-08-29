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
@export var radius: float = 33.0

## Flat attack power per damage type, keyed by CG.DamageType. Enemies skip the
## attribute system; there is no pawn behind them to grow.
@export var attack_power: Dictionary = {}

@export var damage_reduction: float = 0.0

## Issue 542. Multiplier on how fast this enemy gets through an action's
## authored wind-up and recovery; 1.0 is exactly as authored, above 1.0 is
## faster. A pawn gets the same thing from AGI and an enemy had nothing.
@export var action_speed: float = 1.0

@export var actions: Array[StringName] = []

## Issue 685. The `part` an enemy without a `pawn`/`Weapon` draws in its
## `Weapon` slot -- same values as `Weapon.part` (&"sword", &"bow", ...).
@export var weapon_part: StringName = &""

## Tags shown to the player above the health bar.
@export var display_tags: Array[String] = []

## How strongly this enemy prefers a target its allies already attack, 0.0 for
## nearest-and-ignore-everyone to 1.0 for always-join-the-pile.
@export var focus_bias: float = 0.0

## Issue 671. Rows in the same shape a pawn's are, evaluated the same way but
## with no WIS budget -- enemies aren't WIS-limited, so every row here is
## active. Empty falls through to `DefaultPlan`, which is every enemy before
## this field.
@export var plans: Array[Plan] = []

## Issue 756: the same standing preferences `PawnData` carries, since an enemy
## has no plans to hang a row-level override off and these are its only
## per-enemy behaviour dial. Every enemy ships at these defaults, matching
## the behaviour before this field existed -- see `UnitGlobals`.
@export var avoid_hazards: bool = true
@export var target_preference: StringName = &""
@export var posture: StringName = &"seek_enemy"

## Names another enemy **by its `EnemyDef.id`**, resolved to the nearest
## living instance of that type in this fight. A `PawnData.id` has no
## enemy-side equivalent to be unique against -- a room can spawn three rats
## under one `EnemyDef` -- so this names a type, not an instance; "the nearest
## Sellsword" rather than "spawn marker 3's Sellsword". Good enough for a
## bodyguard formation, not for telling two same-type instances apart.
@export var stand_near_ally_id: StringName = &""
