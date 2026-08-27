extends RefCounted
class_name Terrain


## How a room's ground is **authored**: axis-aligned rectangles, in world
## units. `TerrainGrid` is what a fight asks; this is what a room is written in
## and what the level editor edits.

## Issue 625: the queries that used to live here -- `line_is_blocked`,
## `point_is_blocked`, `hazards_at`, `paint`, `subtract` and the Liang-Barsky
## clip under them -- are `TerrainGrid`'s, and answer against cells.
enum Kind {
	WALL,    ## blocks movement and blocks line of sight
	PILLAR,  ## blocks line of sight, does not block movement
	HAZARD,  ## passable, damages a unit standing in it each tick
	PIT,     ## blocks movement, does not block line of sight
	WATER,   ## passable, harmless, and puts out burning ground it touches
}

## Issue 668: Feature is `TerrainFeature`, its own file and a Resource. A plain
## RefCounted inside an exported array is silently dropped on save, which is
## what stopped an encounter being a `.tres`.

static func make(kind: Kind, rect: Rect2) -> TerrainFeature:
	var f := TerrainFeature.new()
	f.kind = kind
	f.rect = rect
	return f

## Issue 492: a pool of water. It does nothing on its own, which is the whole
## of its definition -- no damage, no status, no movement cost.
static func pool(rect: Rect2) -> TerrainFeature:
	return make(Kind.WATER, rect)

## Ground that is on fire, which is the only thing a pool reacts to.
static func is_burning(f) -> bool:
	return f.kind == Kind.HAZARD and f.damage_type == CG.DamageType.FIRE

static func hazard(rect: Rect2, damage_per_tick: int, damage_type: CG.DamageType) -> TerrainFeature:
	var f := make(Kind.HAZARD, rect)
	f.damage_per_tick = damage_per_tick
	f.damage_type = damage_type
	return f
