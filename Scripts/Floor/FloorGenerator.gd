extends RefCounted

const FloorRoom := preload("res://Scripts/Floor/FloorRoom.gd")
const FloorPlan := preload("res://Scripts/Floor/FloorPlan.gd")

## Builds a FloorPlan from a seed. Deterministic: same seed, same rooms, same
## types, same connections, every time — nothing here reads any source of
## randomness but the RandomNumberGenerator this file seeds itself.
##
## OWNER: wren, issue 5.
##
## Shape, not narrative: six ordinary rooms form a randomly-branching but
## always-connected graph rooted at the entrance; exactly one of them is
## picked as the sole gate into a MINIBOSS room; the MINIBOSS is the sole
## connection into the BOSS room, a dead end. That makes "the boss is
## unreachable without passing the miniboss" true by construction — remove
## the miniboss node and the boss becomes unreachable, which
## FloorPlan.reachable_excluding proves directly rather than the generator
## promising it.

## README.md: floor 1 has 8 rooms. Two of them (miniboss, boss) are fixed;
## the rest are ordinary rooms.
const FLOOR_1_ROOM_COUNT := 8
const _GATE_TYPE_COUNT := 2 # miniboss + boss
const _ORDINARY_ROOM_COUNT := FLOOR_1_ROOM_COUNT - _GATE_TYPE_COUNT

const _ORDINARY_TYPES: Array[FloorRoom.Type] = [
	FloorRoom.Type.ENEMY,
	FloorRoom.Type.BIG_ENEMY,
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

	for i in _ORDINARY_ROOM_COUNT:
		var r := FloorRoom.new()
		r.id = i
		r.type = _ORDINARY_TYPES[rng.randi_range(0, _ORDINARY_TYPES.size() - 1)]
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
