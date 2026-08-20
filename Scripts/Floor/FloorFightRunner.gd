extends RefCounted
class_name FloorFightRunner


## Plays one fight-bearing room of a FloorRun for real, through CombatSim, and
## writes the result back. This is the connection issue 5 left for later: the
## floor graph and the party state existed, nothing ran a fight from them.

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

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run.plan.seed, room.id])
	var item := LootTables.roll_drop(room.type, room.difficulty, rng)
	if item != null:
		run.add_loot(item)
	run.enter(room.id)

## README's CELL: "a selection of new pawns (pick one)". This is the
## attrition counterweight issue 7 needs -- dace's own recovery-curve finding
## was that four different curves all land on the same two numbers, so a run
## that grinds a party down needs something other than a bigger heal. CELL
## replaces a loss; it does not undo one.
const CELL_CANDIDATE_COUNT := 3

static func cell_candidates(run: FloorRun, room: FloorRoom, party: Array[PawnData]) -> Array[PawnData]:
	if room.type != FloorRoom.Type.CELL:
		push_error("FloorFightRunner.cell_candidates: room %d is a %s, not CELL" % [room.id, FloorRoom.type_name(room.type)])
		return []

	var alive_classes := {}
	for p in party:
		if run.is_alive(p.id) and p.pawn_class != null:
			alive_classes[p.pawn_class.id] = true

	var pool: Array[StringName] = []
	for class_id in Registry.all_class_ids():
		if not alive_classes.has(class_id):
			pool.append(class_id)

	## Same determinism rule as every other room roll here: derived from the
	## floor seed and the room id, never a fresh generator.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run.plan.seed, room.id, "cell"])
	_shuffle(rng, pool)

	var out: Array[PawnData] = []
	for i in mini(CELL_CANDIDATE_COUNT, pool.size()):
		var class_id: StringName = pool[i]
		var cls := Registry.get_class_def(class_id)
		var pawn_id := StringName("%s_cell_%d" % [class_id, room.id])
		out.append(PawnFactory.make_starter_pawn(class_id, pawn_id, cls.display_name))
	return out

## Fisher-Yates against a seeded rng, same as FloorGenerator's own -- kept
## here too rather than shared, since the two files do not otherwise depend
## on each other and this is four lines.
static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

## Applies `chosen` (one of cell_candidates' own output) to `party` in
## place -- GDScript arrays are reference types, so this mutates whatever
## array the caller passed, same as record_result already mutates `run` in
## place. Replaces the party's first dead member. Returns whether anything
## changed, so a caller can tell a no-op CELL from a real one.
static func resolve_cell(run: FloorRun, room: FloorRoom, party: Array[PawnData], chosen: PawnData) -> bool:
	if room.type != FloorRoom.Type.CELL:
		push_error("FloorFightRunner.resolve_cell: room %d is a %s, not CELL" % [room.id, FloorRoom.type_name(room.type)])
		return false
	var replaced := false
	for i in party.size():
		if not run.is_alive(party[i].id):
			party[i] = chosen
			replaced = true
			break
	run.enter(room.id)
	return replaced

## Builds a fight from `room` and the party's current condition in `run`,
## runs it to completion, and writes hp/resource/alive back into `run`.
static func play_room(run: FloorRun, room: FloorRoom, party: Array[PawnData], deps: SimDeps = null) -> Dictionary:
	if not is_fight_room(room.type):
		push_error("FloorFightRunner.play_room: room %d is a %s, not a fight room" % [room.id, FloorRoom.type_name(room.type)])
		return {"outcome": Outcome.DEFEAT, "state": null}

	var encounter := _encounter_for(room)
	var fight_seed: int = hash([run.plan.seed, room.id])
	var state := CombatSim.build(party, encounter, fight_seed, deps)

	_carry_party_condition_into(state, run, party)

	CombatSim.run(state, deps)

	for i in party.size():
		var unit := state.unit(i)
		run.record_result(party[i].id, unit.hp, unit.resource, unit.alive)
	run.enter(room.id)

	## Rolled after the fight resolves, using the fight's own seeded rng --
	if state.outcome == CombatState.Outcome.PLAYER_WIN:
		var item := LootTables.roll_drop(room.type, room.difficulty, state.rng)
		if item != null:
			run.add_loot(item)

		_apply_between_room_recovery(run, party)

	return {"outcome": _map_outcome(state.outcome, room.id == run.plan.boss_id), "state": state}

## Rewrites what record_result just stored, applying Balance.between_room_heal
## and Balance.between_room_resource_recover to every living pawn, and
## Balance.revive_hp to every dead one. All three are pure functions of their
## own before/max/has_living_healer -- Balance does not know about FloorRun or
## pawn ids, on purpose, so this is the seam that supplies them. A pawn
## revived this way enters the next room alive but not fully healed
## (REVIVE_HP_FRACTION) and with no resource at all, same "second chance, not
## a free win back" reasoning Balance's own comment states.
static func _apply_between_room_recovery(run: FloorRun, party: Array[PawnData]) -> void:
	var has_living_healer := false
	for p in party:
		if run.is_alive(p.id) and p.pawn_class != null \
				and (p.pawn_class.role_primary == CG.Role.HEALER or p.pawn_class.role_secondary == CG.Role.HEALER):
			has_living_healer = true
			break

	for p in party:
		var hp_max := Balance.max_hp(p)
		if run.is_alive(p.id):
			var healed := Balance.between_room_heal(run.hp_for(p.id, hp_max), hp_max, has_living_healer)
			var resource_max := Balance.max_resource(p)
			var recovered := Balance.between_room_resource_recover(run.resource_for(p.id, resource_max), resource_max)
			run.record_result(p.id, healed, recovered, true)
		else:
			var revived := Balance.revive_hp(hp_max, has_living_healer)
			if revived > 0:
				run.record_result(p.id, revived, 0, true)

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

## The only place this file touches content, and it is a lookup, not a table.
## Which encounter id a `room.type` maps to is a content decision: change the
## ids below, not this function. `enemy_spawns` count is the only thing
## difficulty scales, clamped to that encounter's own spawn list.
const _ENCOUNTER_FOR_TYPE := {
	FloorRoom.Type.ENEMY: &"floor1_room1",
	FloorRoom.Type.BIG_ENEMY: &"floor1_horde",
	FloorRoom.Type.MINIBOSS: &"floor1_ghoul_den",
	FloorRoom.Type.BOSS: &"floor1_warden",
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
