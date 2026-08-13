extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")

## The whole fight. Given the same seed and the same starting units this must
## step to the same state every time, because "change one thing and re-run the
## same fight" is how the combat gets judged.
##
## MANAGER-OWNED SHAPE.
##
## Determinism rules, which apply to every session touching this:
##
##  1. All randomness comes from `rng`. Never `randi()`, never `randf()`, never
##     a new RandomNumberGenerator. Those read a global seed and the fight stops
##     being reproducible without anything looking wrong.
##  2. Never iterate a Dictionary to decide anything that affects the fight.
##     Iterate `units`, which is ordered.
##  3. No `delta`. The simulation advances one whole tick at a time.

enum Outcome { UNRESOLVED, PLAYER_WIN, ENEMY_WIN, DRAW }

var seed: int = 0
var tick: int = 0
var outcome: Outcome = Outcome.UNRESOLVED

## Index in this array is the unit's id and never changes. Dead units stay in
## place with alive == false so ids stay stable for the whole fight.
var units: Array[CombatUnit] = []

var rng: RandomNumberGenerator = null

## Every event since the fight began, in tick order. The view reads from
## `events_since` rather than clearing this, so the log survives a scrub.
var events: Array[CombatEvent] = []

func _init(fight_seed: int = 0) -> void:
	seed = fight_seed
	rng = RandomNumberGenerator.new()
	rng.seed = fight_seed

func unit(id: int) -> CombatUnit:
	if id < 0 or id >= units.size():
		return null
	return units[id]

func living(team: CG.Team) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	for u in units:
		if u.alive and u.team == team:
			out.append(u)
	return out

## Events emitted at or after `from_index`. The view keeps its own cursor.
func events_since(from_index: int) -> Array[CombatEvent]:
	if from_index <= 0:
		return events.duplicate()
	if from_index >= events.size():
		return []
	return events.slice(from_index)

func emit(e: CombatEvent) -> void:
	events.append(e)
