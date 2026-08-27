extends SceneTree

## Issue 330: ranged attacks fired in `floor1_cover` against the same room with
## its pillars removed. Reads events and observed positions after
## `CombatSim.step` and never calls `decide`, per #329.

const SEEDS := 10

func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	_score("pillars", enc)
	_score("paint", _without_terrain(enc))
	quit(0)

func _score(label: String, enc: RoomData) -> void:
	var fires := 0
	var unit_ticks := 0
	var ticks := 0
	for ids in _parties():
		for seed in SEEDS:
			var state := CombatSim.build(_pawns(ids, seed), enc, seed, SimDeps.new())
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				for u in state.units:
					if u.alive:
						unit_ticks += 1
			ticks += state.tick
			for e in state.events:
				if e.kind == CG.EventKind.ACTION_FIRE and _is_ranged(e.action_id):
					fires += 1
	print("%-8s ranged fires %6d over %7d living unit-ticks = %.2f per 1000; mean fight %d ticks" % [
		label, fires, unit_ticks, 1000.0 * float(fires) / float(maxi(1, unit_ticks)), ticks / 50])

func _is_ranged(action_id: StringName) -> bool:
	var a := Registry.get_action(action_id)
	return a != null and not a.heals and a.requires_line_of_sight and a.range_units > 60.0

func _without_terrain(enc: RoomData) -> RoomData:
	var e := RoomData.new()
	e.id = enc.id
	e.display_name = enc.display_name
	e.enemy_spawns = enc.enemy_spawns
	e.party_spawns = enc.party_spawns
	return e

func _parties() -> Array:
	var names := PackedStringArray()
	for id in Registry.all_class_ids():
		names.append(String(id))
	names.sort()
	var out := []
	for skip in names.size():
		var party: Array[StringName] = []
		for i in names.size():
			if i != skip:
				party.append(StringName(names[i]))
		out.append(party)
	return out

func _pawns(ids: Array, seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(ids[i], StringName("%s_%d_%d" % [ids[i], seed, i]), String(ids[i])))
	return out
