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
## room. `alive == false` sticks until a revive room; see REVIVE_EVERY_N_ROOMS.
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

## Issue 796: a fraction of MISSING HP, healed on arrival in the next room,
## living pawns only, no revive. Never reaches full, so no room is free.
const BETWEEN_ROOM_HEAL_MISSING_FRACTION := 0.5

## Issue 802: how often a fallen pawn comes back, and at what share of max hp.
## `static var` rather than `const` so one build can sweep several settings
## from the command line; nothing but Tools/ ever assigns them.
static var REVIVE_EVERY_N_ROOMS := 0
static var REVIVE_AT_HP_FRACTION := 0.5

## The camp room: one revive per floor, found somewhere and kept until it is
## needed, so it fires on the first arrival with two or more of the party
## down. #797 put the cliff at the second death. Set true and the cadence
## above is ignored. This is roughly optimal play, not the camp itself.
static var REVIVE_ONCE_ON_TWO_DOWN := true

## Set when the camp's one revive is spent. Still false at the end of a floor
## means the run never got two pawns down and never used it.
var revive_used: bool = false

## True on arrival at 0-based `room_index` under the cadence. Room 0 is never
## a revive room: nobody has died yet.
static func revives_on_arrival(room_index: int) -> bool:
	if REVIVE_EVERY_N_ROOMS <= 0:
		return false
	return room_index > 0 and room_index % REVIVE_EVERY_N_ROOMS == 0

## The whole decision for one arrival, cadence or camp.
static func should_revive(run: FloorRun, party: Array[PawnData], room_index: int) -> bool:
	if not REVIVE_ONCE_ON_TWO_DOWN:
		return revives_on_arrival(room_index)
	if run.revive_used or room_index < 1:
		return false
	return run.down_count(party) >= 2

func down_count(party: Array[PawnData]) -> int:
	var n := 0
	for p in party:
		if not is_alive(p.id):
			n += 1
	return n

## Overwrites `state`'s party units (index i is party[i], the order
## `CombatSim.build` always places them in) with what this run carried from
## the last room, then applies the arrival heal above. Shared by BattleView's
## live floor and Tools/FloorRuns.gd's headless sweep so the carry rule and
## the heal have exactly one implementation.
static func carry_into(run: FloorRun, state: CombatState, party: Array[PawnData], room_index: int = 0) -> void:
	var revive := should_revive(run, party, room_index)
	if revive:
		run.revive_used = true
	for i in party.size():
		var unit := state.unit(i)
		var pawn_id: StringName = party[i].id
		_commit_staged_plan(party[i])
		if not run.is_alive(pawn_id):
			if not revive:
				unit.alive = false
				unit.hp = 0
				continue
			_revive(state, run, unit, pawn_id)
			continue
		unit.hp = clampi(run.hp_for(pawn_id, unit.hp_max), 0, unit.hp_max)
		unit.resource = clampi(run.resource_for(pawn_id, unit.resource_max), 0, unit.resource_max)
		_apply_arrival_heal(state, unit)

## Issue 741: a plan edited while its owner's fight was running lands in
## `staged_plans` rather than `plans`, so the fight it started in stays
## reproducible. This is the commit point -- room arrival, the same moment hp
## and resource already carry across. A dead pawn's edits commit too: `plans`
## is what the next fight it joins will read, regardless of this one's result.
static func _commit_staged_plan(pawn: PawnData) -> void:
	if not pawn.plans_staged:
		return
	pawn.plans = pawn.staged_plans
	pawn.staged_plans = []
	pawn.plans_staged = false
	pawn.plans_edited = false

## Issue 802: a fallen pawn returns at REVIVE_AT_HP_FRACTION of max, with no
## resource, and does NOT also take the arrival heal in the same room. At
## least 1 hp, so a small pool rounding to zero cannot arrive dead.
static func _revive(state: CombatState, run: FloorRun, unit: CombatUnit, pawn_id: StringName) -> void:
	unit.alive = true
	unit.hp = maxi(1, int(round(float(unit.hp_max) * REVIVE_AT_HP_FRACTION)))
	unit.resource = 0
	run.record_result(pawn_id, unit.hp, 0, true)
	var e := CombatEvent.make(CG.EventKind.HEAL, state.tick)
	e.target_id = unit.id
	e.amount = unit.hp
	state.emit(e)

## Living pawn only, no revive: `carry_into` already set dead units aside
## above and this never runs on one. A pawn already at max hp emits nothing,
## same "no event for no change" rule `CombatSim._apply_heal` uses.
static func _apply_arrival_heal(state: CombatState, unit: CombatUnit) -> void:
	var amount := int(round(float(unit.hp_max - unit.hp) * BETWEEN_ROOM_HEAL_MISSING_FRACTION))
	var before := unit.hp
	unit.hp = mini(unit.hp_max, unit.hp + amount)
	var applied := unit.hp - before
	if applied <= 0:
		return
	var e := CombatEvent.make(CG.EventKind.HEAL, state.tick)
	e.target_id = unit.id
	e.amount = applied
	state.emit(e)
