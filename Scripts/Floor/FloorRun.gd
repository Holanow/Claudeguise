extends RefCounted

const FloorPlan := preload("res://Scripts/Floor/FloorPlan.gd")

## Tracks one traversal of a generated FloorPlan: where the party is, which
## rooms have been visited, and what carried over from the last room each
## pawn fought in.
##
## OWNER: wren, issue 5. Deliberately does not call CombatSim or know what a
## CombatUnit is — issue 5's boundary is the floor model, not the fight.
## Wiring a room's fight to the simulation is a separate issue.

var plan: FloorPlan
var current_room_id: int = -1
var visited: Array[int] = []

## Keyed by pawn id (StringName). No entry means "not yet fought a room" and
## every reader here treats that as full health / alive, matching a pawn
## that has not been touched yet.
var carry: Dictionary = {}

func _init(floor_plan: FloorPlan) -> void:
	plan = floor_plan
	current_room_id = floor_plan.entrance_id
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
