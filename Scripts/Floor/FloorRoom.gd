extends RefCounted
class_name FloorRoom

## One room in a generated floor. Says where it sits on the grid and which
## authored room scene fills it. It never lists what it connects to: adjacency
## on the grid IS the connection, and `FloorPlan.neighbours_of` derives it.

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

## Grid cell. +x is east, +y is south, matching screen coordinates.
var cell: Vector2i = Vector2i.ZERO

## The authored room scene this cell holds -- a `RoomLibrary` id.
var content_id: StringName = &""

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
