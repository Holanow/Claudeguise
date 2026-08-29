extends SceneTree

## Issue 792. FloorRuns.gd reports depth and clear count only; this reports
## what a cleared arm B run's party looks like at the end -- hp fraction and
## alive/dead per pawn, per #730's "winning narrowly" target. Planned pawns
## only, same 40 seeds FloorRuns.gd uses.

const SEEDS := 40

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	if class_ids.is_empty():
		printerr("no classes registered")
		quit(1)
		return
	print("Cleared-run final state, issue 792, %d seeds, arm B (planned).\n" % SEEDS)
	for s in range(SEEDS):
		var room_ids := FloorSequence.build(s)
		var party: Array[PawnData] = []
		for cid in class_ids:
			var c := StringName(cid)
			var display := ClassLibrary.get_class_def(c).display_name
			party.append(PawnFactory.make_preset_pawn(c, c, display))
		var run := FloorRun.new()
		var wiped := false
		var last_state: CombatState = null
		for i in room_ids.size():
			var room_id: StringName = room_ids[i]
			var state := CombatSim.build(party, RoomLibrary.get_room(room_id), hash([s, room_id, i]))
			FloorRun.carry_into(run, state, party)
			CombatSim.run(state)
			last_state = state
			for j in party.size():
				var unit := state.unit(j)
				run.record_result(party[j].id, unit.hp, unit.resource, unit.alive)
			if state.outcome != CombatState.Outcome.PLAYER_WIN:
				wiped = true
				break
		if wiped:
			continue
		print("seed %d cleared:" % s)
		for j in party.size():
			var unit := last_state.unit(j)
			var pct := 0
			if unit.hp_max > 0:
				pct = int(round(100.0 * unit.hp / unit.hp_max))
			print("  %-14s %s  hp %d/%d (%d%%)" % [
				String(party[j].id), "alive" if unit.alive else "DEAD",
				unit.hp, unit.hp_max, pct])
	quit(0)
