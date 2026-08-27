extends Resource
class_name Encounter

## One room's worth of fight: which enemies, and where everyone starts.
## MANAGER-OWNED SHAPE. Spawn points are authored, not generated.

@export var id: StringName = &""
@export var display_name: String = ""

## Whether the room picker offers this encounter. Content is the single source;
## `PartySelect` and the tests both query it rather than restating it (#180).
@export var pickable: bool = false

## One entry per enemy: { "enemy_id": StringName, "position": Vector2 }.
@export var enemy_spawns: Array[Dictionary] = []

## Party start points, in party order. A short list means the sim places the rest.
@export var party_spawns: Array[Vector2] = []

## `TerrainFeature` walls, pillars, hazards and pits. Untyped to match
## `Terrain.gd`'s API. Copied onto `CombatState` by `CombatSim.build`.
@export var terrain: Array = []
