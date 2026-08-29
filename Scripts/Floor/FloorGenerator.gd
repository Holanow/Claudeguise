extends RefCounted
class_name FloorGenerator


## Builds a FloorPlan from a seed, Isaac-style: grow a scatter of cells out from
## the entrance, then hang the miniboss and the boss off dead ends. Deterministic
## -- nothing here reads any source of randomness but the
## RandomNumberGenerator it seeds itself.

## Issue 804: the generator places the ten authored room ids directly rather
## than staying abstract. There are no treasure, library or cell scenes, so four
## of the eight `FloorRoom.Type` values have nowhere to land, and a pool that
## can produce a room nothing can draw is a defect waiting for a seed.
const ORDINARY_IDS: Array[StringName] = [
	&"floor1_room1", &"floor1_horde", &"floor1_ghoul_den", &"floor1_cover",
	&"floor1_hazard", &"floor1_chokepoint", &"floor1_sellsword", &"floor1_narrows_elite",
]
const MINIBOSS_ID: StringName = &"floor1_rat_king"
const BOSS_ID: StringName = &"floor1_warden"

const FLOOR_1_ROOM_COUNT := 10

static func generate(floor_seed: int) -> FloorPlan:
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed

	var plan := FloorPlan.new()
	plan.seed = floor_seed

	var order := ORDINARY_IDS.duplicate()
	_shuffle(rng, order)

	var cells := _scatter(rng, order.size())
	for i in order.size():
		plan.rooms.append(_make_room(i, order[i], FloorRoom.Type.ENEMY, cells[i], 1))
	plan.index_cells()

	## The miniboss goes on a free cell with exactly one placed neighbour, the
	## boss on a free cell next to it with none. Placing the boss last is what
	## makes the gate hold: nothing lands beside it afterwards, so grid
	## adjacency can never grow it a second door.
	var gate := _pick_gate_cells(rng, cells)
	plan.rooms.append(_make_room(order.size(), MINIBOSS_ID, FloorRoom.Type.MINIBOSS, gate[0], 5))
	plan.rooms.append(_make_room(order.size() + 1, BOSS_ID, FloorRoom.Type.BOSS, gate[1], 10))
	plan.index_cells()

	plan.entrance_id = 0
	plan.miniboss_id = order.size()
	plan.boss_id = order.size() + 1
	return plan

static func _make_room(id: int, content_id: StringName, type: FloorRoom.Type, cell: Vector2i, difficulty: int) -> FloorRoom:
	var r := FloorRoom.new()
	r.id = id
	r.content_id = content_id
	r.type = type
	r.cell = cell
	r.difficulty = difficulty
	return r

## Isaac's growth step: the entrance sits at the origin, and every later room
## attaches to a free cell orthogonally adjacent to an already-placed one. The
## result is always connected, and never has two rooms in one cell.
static func _scatter(rng: RandomNumberGenerator, count: int) -> Array[Vector2i]:
	var placed: Array[Vector2i] = [Vector2i.ZERO]
	var taken := {Vector2i.ZERO: true}
	while placed.size() < count:
		var options := _free_neighbours(placed, taken)
		var cell: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		placed.append(cell)
		taken[cell] = true
	return placed

static func _free_neighbours(placed: Array[Vector2i], taken: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	for cell in placed:
		for dir in FloorPlan.DIRECTIONS:
			var c: Vector2i = cell + dir
			if taken.has(c) or seen.has(c):
				continue
			seen[c] = true
			out.append(c)
	return out

## Returns `[miniboss_cell, boss_cell]`. A pair always exists: take the placed
## cell furthest east (ties to the south), step east twice, and neither of those
## two cells can touch anything placed except through the other.
static func _pick_gate_cells(rng: RandomNumberGenerator, placed: Array[Vector2i]) -> Array[Vector2i]:
	var taken := {}
	for cell in placed:
		taken[cell] = true

	var pairs: Array = []
	for m in _free_neighbours(placed, taken):
		if _placed_neighbour_count(m, taken) != 1:
			continue
		for dir in FloorPlan.DIRECTIONS:
			var b: Vector2i = m + dir
			if taken.has(b) or b == m:
				continue
			if _placed_neighbour_count(b, taken) == 0:
				pairs.append([m, b])
	var pick: Array = pairs[rng.randi_range(0, pairs.size() - 1)]
	var out: Array[Vector2i] = []
	out.assign(pick)
	return out

static func _placed_neighbour_count(cell: Vector2i, taken: Dictionary) -> int:
	var n := 0
	for dir in FloorPlan.DIRECTIONS:
		if taken.has(cell + dir):
			n += 1
	return n

## Fisher-Yates against the floor's own seeded rng -- Array.shuffle() reads the
## engine's global RNG, which would break "same seed, same floor."
static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
