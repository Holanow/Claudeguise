extends SceneTree

## Issue 730: the floor's only balance question. Arm A -- default pawns, no
## plan rows, the fallback decides everything -- should basically always
## lose. Arm B -- the same classes carrying their preset plans -- should win
## sometimes. Same seeds, both arms, side by side, and where each run ends.
##
## Issue 734: clear rate alone cannot distinguish the two arms while both sit
## at 0/40 -- depth reached (how many rooms a run survives before it dies, or
## all of them if it clears) is what tells arm B apart from arm A when
## neither wins.

const SEEDS := 40

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	if class_ids.is_empty():
		printerr("no classes registered")
		quit(1)
		return
	print("Floor runs, issue 730/734: arm A (default) vs arm B (planned), %d seeds.\n" % SEEDS)
	_report("Arm A -- default pawns, no plans", _run_arm(class_ids, false))
	_report("Arm B -- planned pawns", _run_arm(class_ids, true))
	quit(0)

func _run_arm(class_ids: Array, planned: bool) -> Dictionary:
	var cleared := 0
	var died_at := {}
	var depths: Array[int] = []
	for s in range(SEEDS):
		var room_ids := FloorWalk.default_order(FloorGenerator.generate(s))
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
				## 1-based: died in the i-th room means it survived i rooms
				## before this one, i.e. reached depth i + 1.
				depths.append(i + 1)
				break
		if not wiped:
			cleared += 1
			depths.append(room_ids.size())
	return {"cleared": cleared, "died_at": died_at, "depths": depths}

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
	_report_depth(r.depths, r.cleared)
	print("")

## Issue 734: how many rooms a run entered before it ended. Mean alone hides
## "usually 4, occasionally 9" behind "6.5" -- min/median/max plus the
## per-depth histogram carry the spread mean cannot.
func _report_depth(depths: Array[int], cleared: int) -> void:
	var sorted := depths.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0
	for d in sorted:
		total += d
	var mean := float(total) / n
	var median: float = float(sorted[n / 2]) if n % 2 == 1 \
		else (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
	print("  depth reached (last room the run entered; depth 10 is not by itself a clear):")
	print("    min %d, median %.1f, mean %.1f, max %d" % [sorted[0], median, mean, sorted[n - 1]])
	var histogram := {}
	for d in sorted:
		histogram[d] = int(histogram.get(d, 0)) + 1
	var line := "    "
	for depth in range(1, 11):
		var count: int = histogram.get(depth, 0)
		line += "%d:%d  " % [depth, count]
	print(line)
	## Issue 799: a run that dies IN the tenth room reaches depth 10 as well, so
	## the last bucket is not the clear count and was read as one.
	var deepest: int = histogram.get(10, 0)
	print("    of the %d at depth 10: %d cleared, %d died in the last room" % [
		deepest, cleared, deepest - cleared])
