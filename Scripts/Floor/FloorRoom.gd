extends RefCounted
class_name FloorRoom

## One room in a generated floor's graph. Says what kind of room this is and
## what it connects to; never what it contains. `Scripts/Content/**` fills a
## room in from `type` and `difficulty` -- a FloorRoom says "this is an enemy
## room with difficulty 3", never which enemies.

enum Type {
	ENEMY,
	BIG_ENEMY,
	TRAP,
	TREASURE,
	LIBRARY,
	CELL,
	MINIBOSS,
	BOSS,
}

## Stable within one generated floor. Index into FloorPlan.rooms.
var id: int = -1

var type: Type = Type.ENEMY

## Room ids this one connects to. Symmetric: if a connects to b, b connects
## to a. A room graph, not a directed one -- nothing in this slice needs a
## one-way door.
var connections: Array[int] = []

## Content-agnostic difficulty knob. What it means is entirely
## Scripts/Content/'s call; FloorRoom only carries the number.
var difficulty: int = 1

static func type_name(t: Type) -> String:
	match t:
		Type.ENEMY: return "Enemy"
		Type.BIG_ENEMY: return "Big Enemy"
		Type.TRAP: return "Trap"
		Type.TREASURE: return "Treasure"
		Type.LIBRARY: return "Library"
		Type.CELL: return "Cell"
		Type.MINIBOSS: return "Miniboss"
		Type.BOSS: return "Boss"
	return "?"
