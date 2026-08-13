extends Resource

## One room's worth of fight: which enemies, where they and the party start.
##
## MANAGER-OWNED SHAPE. The slice's single encounter lives in
## Scripts/Content/Encounters/ and belongs to teal.
##
## Spawn positions are explicit rather than generated. The slice is one hand
## authored room, and a procedural layout would put a second variable in front
## of the question being asked.

@export var id: StringName = &""
@export var display_name: String = ""

## One entry per enemy. Each is { "enemy_id": StringName, "position": Vector2 }.
@export var enemy_spawns: Array[Dictionary] = []

## Where party members stand, in party order. Shorter than the party means the
## remaining pawns are placed by the simulation behind the last given point.
@export var party_spawns: Array[Vector2] = []
