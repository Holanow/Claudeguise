extends SceneTree

## Issue 730: the floor's only balance question. Arm A -- default pawns, no
## plan rows, the fallback decides everything -- should basically always
## lose. Arm B -- the same classes carrying their preset plans -- should win
## sometimes. Same seeds, both arms, side by side, and where each run ends.

const SEEDS := 40

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	if class_ids.is_empty():
		printerr("no classes registered")
		quit(1)
		return
	print("Floor runs, issue 730: arm A (default) vs arm B (planned), %d seeds, no healing between rooms.\n" % SEEDS)
	_report("Arm A -- default pawns, no plans", _run_arm(class_ids, false))
	_report("Arm B -- planned pawns", _run_arm(class_ids, true))
	quit(0)

func _run_arm(class_ids: Array, planned: bool) -> Dictionary:
	var cleared := 0
	var died_at := {}
	for s in range(SEEDS):
		var room_ids := FloorSequence.build(s)
		var party := _make_party(class_ids, planned)
		var run := FloorRun.new()
		var wiped := false
		for i in room_ids.size():
			var room_id: StringName = room_ids[i]
			var state := CombatSim.build(party, RoomLibrary.get_room(room_id), hash([s, room_id, i]))
			FloorRun.carry_into(run, state, party)
			CombatSim.run(state)
			for j in party.size():
				var unit := state.unit(j)
				run.record_result(party[j].id, unit.hp, unit.resource, unit.alive)
			if state.outcome != CombatState.Outcome.PLAYER_WIN:
				wiped = true
				died_at[room_id] = int(died_at.get(room_id, 0)) + 1
				break
		if not wiped:
			cleared += 1
	return {"cleared": cleared, "died_at": died_at}

func _make_party(class_ids: Array, planned: bool) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for cid in class_ids:
		var c := StringName(cid)
		var display := ClassLibrary.get_class_def(c).display_name
		party.append(PawnFactory.make_preset_pawn(c, c, display) if planned \
			else PawnFactory.make_starter_pawn(c, c, display))
	return party

func _report(label: String, r: Dictionary) -> void:
	print(label)
	print("  cleared the floor: %d of %d (%d%%)" % [r.cleared, SEEDS, int(round(100.0 * r.cleared / SEEDS))])
	var died_at: Dictionary = r.died_at
	if died_at.is_empty():
		print("  no losses")
	else:
		print("  died at:")
		var ids: Array = died_at.keys()
		ids.sort_custom(func(a, b): return String(a) < String(b))
		for room_id in ids:
			var n: int = died_at[room_id]
			print("    %-24s %d (%d%%)" % [String(room_id), n, int(round(100.0 * n / SEEDS))])
	print("")
