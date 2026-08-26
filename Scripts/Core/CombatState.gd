extends RefCounted
class_name CombatState


## The whole fight. Given the same seed and the same starting units this must
## step to the same state every time, because "change one thing and re-run the
## same fight" is how the combat gets judged.

enum Outcome { UNRESOLVED, PLAYER_WIN, ENEMY_WIN, DRAW }

var seed: int = 0
var tick: int = 0
var outcome: Outcome = Outcome.UNRESOLVED

## Index in this array is the unit's id and never changes. Dead units stay in
## place with alive == false so ids stay stable for the whole fight.
var units: Array[CombatUnit] = []

var rng: RandomNumberGenerator = null

## The ground, as cells. Issue 625: this replaces the array of rectangles, so
## a cell is one kind of ground or it is nothing. Never reassigned after
## `build()` -- `BattleView` hands it to `ArenaFloor` once and it mutates in
## place, the same contract `units` already has.
var grid: TerrainGrid = TerrainGrid.new()

## Shots in flight or already resolved, in launch order. Append-only like
## units, for the same reason: nothing external references one by id today,
## but the array must not reshuffle out from under mid-tick iteration.
var projectiles: Array[Projectile] = []

## Index of the first unresolved entry in `projectiles`, so the per-tick scan
## does not walk thousands of already-resolved entries in a long fight.
var next_unresolved_projectile: int = 0

## Every event since the fight began, in tick order. The view reads from
## `events_since` rather than clearing this, so the log survives a scrub.
var events: Array[CombatEvent] = []

## Issue 588: the enemy the player clicked, party-wide, and -1 when none.
## Deliberately not `unit.focus_id`, which CombatSim overwrites at every action
## commit and which #505 gave to cover.
var player_focus_id: int = -1

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
