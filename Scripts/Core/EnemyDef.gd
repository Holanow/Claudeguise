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
## Drawing only, same as CombatUnit.radius. Raised from 12.0 for legibility.
@export var radius: float = 22.0

## Flat attack power per damage type, keyed by CG.DamageType. Enemies skip the
## attribute system entirely; there is no pawn behind them to grow.
@export var attack_power: Dictionary = {}

@export var damage_reduction: float = 0.0

@export var actions: Array[StringName] = []

## Tags shown to the player above the health bar.
@export var display_tags: Array[String] = []

## How strongly this enemy prefers a target its allies are already attacking,
## from 0.0 (pick the nearest, ignore what everyone else is doing) to 1.0
## (join the pile whenever there is one).
##
## Added for teal's diagnosis on issue 7: more enemies currently means more
## total damage rather than concentrated damage, because every enemy
## independently picks its own nearest pawn. A party of four absorbs spread
## damage very well and dies to concentrated damage, which is why wins cost
## 20% of the party's hp and never a casualty.
##
## Deliberately per-enemy rather than a global rule, because it is a design
## lever and not a difficulty knob: a goblin pack that swarms whoever is already
## bleeding is a different threat from a ghoul that walks at the closest thing,
## and both should be expressible. It is also the readable version — a player can
## see a swarm converge and learn to spread out, which they cannot do about a
## hidden damage multiplier.
##
## The decision layer reads this. The simulation does not: focus is a choice, not
## a rule, and it belongs with the rest of the decision-making.
@export var focus_bias: float = 0.0
