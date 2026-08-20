extends RefCounted
class_name FloorGenerator


## Builds a FloorPlan from a seed. Deterministic: same seed, same rooms, same
## types, same connections, every time -- nothing here reads any source of
## randomness but the RandomNumberGenerator this file seeds itself.

## README.md: floor 1 has 8 rooms. Two of them (miniboss, boss) are fixed;
## the rest are ordinary rooms.
const FLOOR_1_ROOM_COUNT := 8
const _GATE_TYPE_COUNT := 2 # miniboss + boss
const _ORDINARY_ROOM_COUNT := FLOOR_1_ROOM_COUNT - _GATE_TYPE_COUNT

## Issue 5's own finding: picking each of the 6 ordinary rooms uniformly at
## random from all six types let a seed produce a floor with zero fights
## (`Library, Cell, Library, Treasure, Treasure, Cell` -- measured, not
## hypothetical) or zero plain Enemy rooms at all. A floor needs a shape:
const _GUARANTEED_FIGHTS: Array[FloorRoom.Type] = [
	FloorRoom.Type.ENEMY,
	FloorRoom.Type.ENEMY,
	FloorRoom.Type.BIG_ENEMY,
]

## TRAP, LIBRARY and TREASURE are already wired or explicitly scoped by this
## issue (TREASURE: play_treasure_room; CELL: play_cell_room). TRAP has no
## resolution path yet, same as it did before this change -- not this issue's
## gap to close, so it stays in the pool rather than being pulled out, on the
## same footing content already treats it.
const _REWARD_POOL: Array[FloorRoom.Type] = [
	FloorRoom.Type.TRAP,
	FloorRoom.Type.TREASURE,
	FloorRoom.Type.LIBRARY,
	FloorRoom.Type.CELL,
]

static func generate(floor_seed: int) -> FloorPlan:
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed

	var plan := FloorPlan.new()
	plan.seed = floor_seed

	var adjacency := _random_connected_graph(rng, _ORDINARY_ROOM_COUNT)
	var types := _room_types(rng)

	for i in _ORDINARY_ROOM_COUNT:
		var r := FloorRoom.new()
		r.id = i
		r.type = types[i]
		r.difficulty = 1 + i / 2
		r.connections = adjacency[i]
		plan.rooms.append(r)

	var gate_id := rng.randi_range(0, _ORDINARY_ROOM_COUNT - 1)

	var miniboss := FloorRoom.new()
	miniboss.id = _ORDINARY_ROOM_COUNT
	miniboss.type = FloorRoom.Type.MINIBOSS
	miniboss.difficulty = 5
	miniboss.connections = [gate_id]
	plan.rooms.append(miniboss)
	plan.rooms[gate_id].connections.append(miniboss.id)

	var boss := FloorRoom.new()
	boss.id = _ORDINARY_ROOM_COUNT + 1
	boss.type = FloorRoom.Type.BOSS
	boss.difficulty = 10
	boss.connections = [miniboss.id]
	plan.rooms.append(boss)
	miniboss.connections.append(boss.id)

	plan.entrance_id = 0
	plan.miniboss_id = miniboss.id
	plan.boss_id = boss.id

	return plan

## `_GUARANTEED_FIGHTS` plus one roll per remaining ordinary-room slot from
## `_REWARD_POOL`, shuffled together so the fight rooms do not always land on
## the same room ids (which would make "close to the entrance" mean "always a
## fight" by construction, rather than by the graph's own random shape).
static func _room_types(rng: RandomNumberGenerator) -> Array[FloorRoom.Type]:
	var types: Array[FloorRoom.Type] = _GUARANTEED_FIGHTS.duplicate()
	for i in _ORDINARY_ROOM_COUNT - _GUARANTEED_FIGHTS.size():
		types.append(_REWARD_POOL[rng.randi_range(0, _REWARD_POOL.size() - 1)])
	_shuffle(rng, types)
	return types

## Fisher-Yates against the floor's own seeded rng -- Array.shuffle() reads
## the engine's global RNG, which would break "same seed, same floor."
static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

## A random spanning tree over `count` nodes (always connected, node 0 is the
## entrance), plus a handful of extra edges so the floor branches rather than
## reading as one corridor. Each node past the first attaches to a uniformly
## random earlier node, which is enough on its own to guarantee every node is
## reachable from 0.
static func _random_connected_graph(rng: RandomNumberGenerator, count: int) -> Array:
	var adjacency: Array = []
	for i in count:
		adjacency.append([] as Array[int])

	for i in range(1, count):
		var parent := rng.randi_range(0, i - 1)
		adjacency[i].append(parent)
		adjacency[parent].append(i)

	var extra_edges := rng.randi_range(0, 2)
	for i in extra_edges:
		var a := rng.randi_range(0, count - 1)
		var b := rng.randi_range(0, count - 1)
		if a != b and not adjacency[a].has(b):
			adjacency[a].append(b)
			adjacency[b].append(a)

	return adjacency
