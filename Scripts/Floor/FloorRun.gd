extends RefCounted
class_name FloorRun


## Tracks one traversal of a generated FloorPlan: where the party is, which
## rooms have been visited, and what carried over from the last room each
## pawn fought in.

var plan: FloorPlan
var current_room_id: int = -1
var visited: Array[int] = []

## Keyed by pawn id (StringName). No entry means "not yet fought a room" and
## every reader here treats that as full health / alive, matching a pawn
## that has not been touched yet.
var carry: Dictionary = {}

## What the party has picked up this run, in the order rooms dropped it.
var loot: Array[EquipmentDef] = []

## Called when a room resolves and something drops. Records it; does not
## touch any pawn, same as record_result does not touch CombatSim.
func add_loot(item: EquipmentDef) -> void:
	loot.append(item)

## `floor_plan` is optional: issue 729's linear floor sequence has no graph,
## only order, and needs the `carry` bookkeeping below without one.
func _init(floor_plan: FloorPlan = null) -> void:
	plan = floor_plan
	current_room_id = floor_plan.entrance_id if floor_plan != null else -1
	if current_room_id != -1:
		visited.append(current_room_id)

func enter(room_id: int) -> void:
	current_room_id = room_id
	if not visited.has(room_id):
		visited.append(room_id)

## Called once a room's fight is over, to carry a pawn's state into the next
## room. `alive == false` sticks: nothing in this file ever revives a pawn.
func record_result(pawn_id: StringName, hp: int, resource: int, alive: bool) -> void:
	carry[pawn_id] = {"hp": hp, "resource": resource, "alive": alive}

func hp_for(pawn_id: StringName, full_hp: int) -> int:
	if carry.has(pawn_id):
		return int(carry[pawn_id]["hp"])
	return full_hp

func resource_for(pawn_id: StringName, full_resource: int) -> int:
	if carry.has(pawn_id):
		return int(carry[pawn_id]["resource"])
	return full_resource

func is_alive(pawn_id: StringName) -> bool:
	if carry.has(pawn_id):
		return bool(carry[pawn_id]["alive"])
	return true

## Overwrites `state`'s party units (index i is party[i], the order
## `CombatSim.build` always places them in) with what this run carried from
## the last room. No recovery applied -- issue 729 forbids healing between
## rooms. Shared by BattleView's live floor and Tools/FloorRuns.gd's headless
## sweep so the carry rule has exactly one implementation.
static func carry_into(run: FloorRun, state: CombatState, party: Array[PawnData]) -> void:
	for i in party.size():
		var unit := state.unit(i)
		var pawn_id: StringName = party[i].id
		if not run.is_alive(pawn_id):
			unit.alive = false
			unit.hp = 0
			continue
		unit.hp = clampi(run.hp_for(pawn_id, unit.hp_max), 0, unit.hp_max)
		unit.resource = clampi(run.resource_for(pawn_id, unit.resource_max), 0, unit.resource_max)
