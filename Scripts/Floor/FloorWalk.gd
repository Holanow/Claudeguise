extends RefCounted
class_name FloorWalk


## Where the party is on a FloorPlan and which rooms they have already cleared.
## Separate from `FloorRun` -- which carries hp, resource and loot -- only
## because #802 has `FloorRun.gd` open. This state belongs there and should
## move once that lands.

var plan: FloorPlan
var current_id: int = -1
var visited: Array[int] = []

## Room id -> true. A cleared room does not fight again when you walk back
## through it to reach somewhere else.
var _cleared: Dictionary = {}

func _init(floor_plan: FloorPlan) -> void:
	plan = floor_plan
	current_id = floor_plan.entrance_id
	visited.append(current_id)

## The door the party leaves through, in grid directions. This is what a click
## on a drawn door resolves to; the headless walk below picks from the same list.
func exits() -> Array[Dictionary]:
	return plan.exits_of(current_id)

func can_enter(room_id: int) -> bool:
	return plan.neighbours_of(current_id).has(room_id)

func enter(room_id: int) -> void:
	if not can_enter(room_id):
		push_error("FloorWalk.enter: room %d is not adjacent to room %d" % [room_id, current_id])
		return
	current_id = room_id
	if not visited.has(room_id):
		visited.append(room_id)

func mark_cleared(room_id: int) -> void:
	_cleared[room_id] = true

## How many rooms the party has already put behind them. The grid replacement
## for the old walk index: `FloorRun`'s revive cadence and camp rule key on it.
func cleared_count() -> int:
	return _cleared.size()

func is_cleared(room_id: int) -> bool:
	return _cleared.has(room_id)

func is_floor_cleared() -> bool:
	for r in plan.rooms:
		if is_fight(r.id) and not is_cleared(r.id):
			return false
	return true

## Issue 803: the camp is a place, not a fight, so the route never offers it
## and clearing the floor never waits on it.
func is_fight(room_id: int) -> bool:
	var r := plan.room(room_id)
	return r != null and r.type != FloorRoom.Type.CAMP

## The camp is found when the party has stood in a room with a door onto it.
## That is the whole of the run-to-run variance: found early it is available
## across most of the floor, found late it is worth nothing.
func camp_found() -> bool:
	if plan.camp_id < 0:
		return false
	for id in visited:
		if id == plan.camp_id or plan.neighbours_of(id).has(plan.camp_id):
			return true
	return false

## When the party turns round and walks back: the second pawn is down, #797's
## cliff, and the camp has been found and not yet spent. One implementation,
## read by the live floor and by `Tools/FloorRuns.gd`'s sweep.
func wants_camp(run: FloorRun, party: Array[PawnData]) -> bool:
	return not run.revive_used and run.down_count(party) >= 2 and camp_found()

## The walk back to the camp, same shape as `route_to_next_fight`. Empty when
## the floor has no camp or the party is standing in it.
func route_to_camp() -> Array[int]:
	if plan.camp_id < 0:
		return [] as Array[int]
	return _shortest_path(func(id: int) -> bool: return id == plan.camp_id)

## The default route with nobody to click a door: the shortest path from the
## current room to the nearest uncleared one, excluding the current room and
## empty when the floor is done. The boss is held back until it is the only
## room left, which is the one thing `FloorSequence`'s ordered list gave for
## free and a graph does not. A UI replaces this whole function with a click.
func route_to_next_fight() -> Array[int]:
	var boss_only := true
	for r in plan.rooms:
		if r.id != plan.boss_id and is_fight(r.id) and not is_cleared(r.id):
			boss_only = false
			break
	return _shortest_path(func(id: int) -> bool:
		if is_cleared(id) or not is_fight(id):
			return false
		return boss_only or id != plan.boss_id)

## Breadth-first, neighbours taken in `FloorPlan.DIRECTIONS` order so two runs
## of one seed pick the same route.
func _shortest_path(accept: Callable) -> Array[int]:
	var came_from := {current_id: -1}
	var queue: Array[int] = [current_id]
	var head := 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		if at != current_id and accept.call(at):
			return _unwind(came_from, at)
		for next_id in plan.neighbours_of(at):
			if came_from.has(next_id):
				continue
			came_from[next_id] = at
			queue.append(next_id)
	return [] as Array[int]

func _unwind(came_from: Dictionary, target: int) -> Array[int]:
	var path: Array[int] = []
	var at := target
	while at != current_id:
		path.push_front(at)
		at = int(came_from[at])
	return path

## The fight order a headless sweep walks, as authored room ids. One caller of
## the same route function the live floor uses, so the two cannot drift.
static func default_order(plan: FloorPlan) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in default_room_order(plan):
		out.append(plan.room(id).content_id)
	return out

## The same route as `FloorPlan.rooms` indices. A caller that needs a room's
## type or difficulty -- issue 811's drop table does -- cannot get there from a
## content id, which several cells could share.
static func default_room_order(plan: FloorPlan) -> Array[int]:
	var walk := FloorWalk.new(plan)
	var out: Array[int] = []
	out.append(walk.current_id)
	walk.mark_cleared(walk.current_id)
	while true:
		var route := walk.route_to_next_fight()
		if route.is_empty():
			break
		for id in route:
			walk.enter(id)
		out.append(walk.current_id)
		walk.mark_cleared(walk.current_id)
	return out
