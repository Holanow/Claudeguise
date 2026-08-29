extends RefCounted
class_name FloorPlan


## One generated floor: rooms scattered over a grid. Named "FloorPlan" rather
## than "Floor" to keep the built-in `floor()` function unshadowed by any local
## `var floor := ...`.

## The four doors a room can have, in the order `exits_of` returns them.
## +y is south because the grid is drawn in screen coordinates.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]

var seed: int = 0
var rooms: Array[FloorRoom] = []
var entrance_id: int = -1
var miniboss_id: int = -1
var boss_id: int = -1

## cell -> room id. Rebuilt by `index_cells` whenever `rooms` changes; every
## adjacency query below reads it rather than scanning `rooms`.
var _by_cell: Dictionary = {}

func index_cells() -> void:
	_by_cell.clear()
	for r in rooms:
		_by_cell[r.cell] = r.id

func room(id: int) -> FloorRoom:
	if id < 0 or id >= rooms.size():
		return null
	return rooms[id]

func room_at(cell: Vector2i) -> FloorRoom:
	return room(int(_by_cell.get(cell, -1)))

## The connection list, derived rather than stored: two rooms are connected if
## and only if their cells are orthogonally neighbouring. Nothing authors this,
## so nothing can disagree with the layout.
func neighbours_of(id: int) -> Array[int]:
	var out: Array[int] = []
	for e in exits_of(id):
		out.append(int(e["room_id"]))
	return out

## The seam the door UI reads: every room you can leave `id` toward, and the
## grid direction of the door you leave through. `{ "room_id": int,
## "dir": Vector2i }`, in `DIRECTIONS` order so it is stable run to run.
func exits_of(id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r := room(id)
	if r == null:
		return out
	for dir in DIRECTIONS:
		var other := room_at(r.cell + dir)
		if other != null:
			out.append({"room_id": other.id, "dir": dir})
	return out

static func direction_name(dir: Vector2i) -> String:
	match dir:
		Vector2i(0, -1): return "north"
		Vector2i(1, 0): return "east"
		Vector2i(0, 1): return "south"
		Vector2i(-1, 0): return "west"
	return "?"

## Every room id reachable from the entrance, walking grid adjacency.
func reachable_from_entrance() -> Array[int]:
	return _reachable_from(entrance_id, {})

## Every room id reachable from the entrance if `excluded_id` were removed
## from the graph entirely. Used to prove the boss sits behind the miniboss
## rather than assuming it.
func reachable_excluding(excluded_id: int) -> Array[int]:
	if entrance_id == excluded_id:
		return []
	return _reachable_from(entrance_id, {excluded_id: true})

func _reachable_from(start_id: int, blocked: Dictionary) -> Array[int]:
	var seen: Dictionary = {}
	var queue: Array[int] = [start_id]
	while not queue.is_empty():
		var current: int = queue.pop_back()
		if seen.has(current) or blocked.has(current):
			continue
		seen[current] = true
		for next_id in neighbours_of(current):
			if not seen.has(next_id) and not blocked.has(next_id):
				queue.append(next_id)
	var out: Array[int] = []
	for id in seen.keys():
		out.append(id)
	out.sort()
	return out
