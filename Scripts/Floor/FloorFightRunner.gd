extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const FloorRoom := preload("res://Scripts/Floor/FloorRoom.gd")
const FloorRun := preload("res://Scripts/Floor/FloorRun.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const LootTables := preload("res://Scripts/Content/LootTables.gd")

## Plays one fight-bearing room of a FloorRun for real, through CombatSim, and
## writes the result back. This is the connection issue 5 left for later: the
## floor graph and the party state existed, nothing ran a fight from them.
##
## OWNER: wren, issue 9.
##
## Does not touch Scripts/Combat/**: everything here is a caller of
## CombatSim.build/run and a reader/writer of CombatUnit fields it already
## has, exactly the surface those files already expose.

enum Outcome {
	## The party survived and the room was not the boss; the run continues.
	CONTINUES,
	## The party wiped (or drew) this room. The run is over.
	DEFEAT,
	## The party won the boss room. The run is over, the other way.
	VICTORY,
}

## True for the four room types issue 9 wires up. TRAP/TREASURE/LIBRARY/CELL
## have no fight and calling play_room for one is a caller error.
static func is_fight_room(t: FloorRoom.Type) -> bool:
	return t == FloorRoom.Type.ENEMY or t == FloorRoom.Type.BIG_ENEMY \
		or t == FloorRoom.Type.MINIBOSS or t == FloorRoom.Type.BOSS

## TREASURE is the one non-fight room type `LootTables.DROP_CHANCE` knows
## about (always drops) -- everything else in TRAP/LIBRARY/CELL is still
## unbuilt and out of scope here. Not a fight, so no CombatSim involvement
## and no Outcome: a treasure room cannot end a run either way.
static func play_treasure_room(run: FloorRun, room: FloorRoom) -> void:
	if room.type != FloorRoom.Type.TREASURE:
		push_error("FloorFightRunner.play_treasure_room: room %d is a %s, not TREASURE" % [room.id, FloorRoom.type_name(room.type)])
		return

	## Same determinism rule as a fight's own seed: derived from the floor
	## seed and the room id, never a fresh generator, so a treasure room
	## drops the same thing every time the same floor seed visits it.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run.plan.seed, room.id])
	var item := LootTables.roll_drop(room.type, room.difficulty, rng)
	if item != null:
		run.add_loot(item)
	run.enter(room.id)

## Builds a fight from `room` and the party's current condition in `run`,
## runs it to completion, and writes hp/resource/alive back into `run`.
static func play_room(run: FloorRun, room: FloorRoom, party: Array[PawnData], deps: SimDeps = null) -> Outcome:
	if not is_fight_room(room.type):
		push_error("FloorFightRunner.play_room: room %d is a %s, not a fight room" % [room.id, FloorRoom.type_name(room.type)])
		return Outcome.DEFEAT

	var encounter := _encounter_for(room)
	## Derived from the floor seed and the room id, never from a fresh
	## generator: the same floor seed must play the same floor the same way,
	## and this is what makes every room's fight reproducible without
	## FloorRun carrying its own seed state.
	var fight_seed: int = hash([run.plan.seed, room.id])
	var state := CombatSim.build(party, encounter, fight_seed, deps)

	_carry_party_condition_into(state, run, party)

	CombatSim.run(state, deps)

	for i in party.size():
		var unit := state.unit(i)
		run.record_result(party[i].id, unit.hp, unit.resource, unit.alive)
	run.enter(room.id)

	## Rolled after the fight resolves, using the fight's own seeded rng --
	## same reasoning as issue 20's regen and issue 7's damage variance: a
	## drop roll needs a real, seeded source or "same floor seed, same
	## floor" stops being true. Only on a win: a wiped party does not loot
	## the room that wiped it.
	if state.outcome == CombatState.Outcome.PLAYER_WIN:
		var item := LootTables.roll_drop(room.type, room.difficulty, state.rng)
		if item != null:
			run.add_loot(item)

	return _map_outcome(state.outcome, room.id == run.plan.boss_id)

## Pulled out of play_room so the win/loss/boss mapping is testable without
## needing a real fight to reach each branch.
static func _map_outcome(sim_outcome: CombatState.Outcome, room_is_boss: bool) -> Outcome:
	if sim_outcome != CombatState.Outcome.PLAYER_WIN:
		return Outcome.DEFEAT
	if room_is_boss:
		return Outcome.VICTORY
	return Outcome.CONTINUES

## Overwrites each party CombatUnit's hp/resource/alive with what FloorRun
## carried from the last room, in place, right after build() and before the
## fight starts. build() has no way to know about a previous room; this is
## the seam for it, using only fields CombatUnit already has.
static func _carry_party_condition_into(state: CombatState, run: FloorRun, party: Array[PawnData]) -> void:
	for i in party.size():
		var unit := state.unit(i)
		var pawn_id := party[i].id
		if not run.is_alive(pawn_id):
			unit.alive = false
			unit.hp = 0
			continue
		unit.hp = clampi(run.hp_for(pawn_id, unit.hp_max), 0, unit.hp_max)
		unit.resource = clampi(run.resource_for(pawn_id, unit.resource_max), 0, unit.resource_max)

## The only place this file touches content, and it is a lookup, not a
## table. Issue 27 found that every room.type used to fall through to
## `floor1_room1` regardless, so difficulty could only ever change *how
## many* of that one melee-first spawn list showed up -- against a party
## that outranges the front of that list, no difficulty number moved
## anything. `_ENCOUNTER_FOR_TYPE` is the placeholder fix: which encounter
## id a room.type maps to is a content decision and teal's to retune, not
## wren's to guess well -- change the ids below, not this function, when
## better ones exist. `enemy_spawns` *count* is still the only thing
## difficulty is allowed to scale, clamped to whichever encounter's own
## spawn list.
##
## First floor phase: MINIBOSS and BOSS no longer share an id. Real boss
## content (The Warden, the Rat King) is item D, not this change -- until
## it exists, BOSS points at the toughest thing already registered
## (`floor1_chokepoint`: the full 10-enemy roster behind a wall, the
## hardest fight in the game today) rather than reusing MINIBOSS's
## `floor1_ghoul_den` verbatim. `floor1_cover` and `floor1_hazard` remain
## unused by any room type; flagged on the board rather than folded in
## here without asking, since it's not the smallest change.
const _ENCOUNTER_FOR_TYPE := {
	FloorRoom.Type.ENEMY: &"floor1_room1",
	FloorRoom.Type.BIG_ENEMY: &"floor1_horde",
	FloorRoom.Type.MINIBOSS: &"floor1_ghoul_den",
	FloorRoom.Type.BOSS: &"floor1_chokepoint",
}

static func _encounter_for(room: FloorRoom) -> Encounter:
	var encounter_id: StringName = _ENCOUNTER_FOR_TYPE.get(room.type, &"floor1_room1")
	var base := Registry.get_encounter(encounter_id)
	var scaled := Encounter.new()
	scaled.id = base.id
	scaled.display_name = base.display_name
	scaled.party_spawns = base.party_spawns
	scaled.terrain = base.terrain
	var count := clampi(room.difficulty, 1, base.enemy_spawns.size())
	scaled.enemy_spawns = base.enemy_spawns.slice(0, count)
	return scaled
