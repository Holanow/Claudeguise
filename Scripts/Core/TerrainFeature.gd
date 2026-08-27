extends Resource
class_name TerrainFeature

## One piece of terrain. A Resource rather than a plain RefCounted, and that is
## the whole of issue 668: `ResourceSaver.save` returns `err == 0` and silently
## DROPS a plain RefCounted inside an exported array. Right count, right
## structure, no error, every feature gone. An encounter could not be a `.tres`
## until this was one.

@export var kind: Terrain.Kind = Terrain.Kind.WALL
@export var rect: Rect2 = Rect2()

## HAZARD only. Damage per tick to a unit standing on ground this stamps.
@export var damage_per_tick: int = 0
@export var damage_type: CG.DamageType = CG.DamageType.PHYSICAL

@export var applies_status: CG.Status = CG.Status.SHIELD
@export var applies_status_enabled: bool = false
@export var status_duration_ticks: int = 0

## How hard the applied status hits, for the statuses whose whole damage rate is
## a multiple of a magnitude the applying hit normally supplies.
@export var status_magnitude: float = 0.0

func blocks_movement() -> bool:
	return kind == Terrain.Kind.WALL or kind == Terrain.Kind.PIT

func blocks_sight() -> bool:
	return kind == Terrain.Kind.WALL or kind == Terrain.Kind.PILLAR
