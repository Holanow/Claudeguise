extends SceneTree

## Issue 730: the floor's only balance question. Arm A -- default pawns, no
## plan rows, the fallback decides everything -- should basically always
## lose. Arm B -- the same classes carrying their preset plans -- should win
## sometimes. Same seeds, both arms, side by side, and where each run ends.
##
## Issue 734: depth reached, because clear rate cannot separate two arms at 0/40.
## Issue 808: the party is four. Every composition, unless --party names one.
## Issue 817: `--final-state` prints the per-pawn end state of the runs that
## cleared or came within one room of it, off this loop rather than off a
## second copy of it.

const SEEDS := 40

## Runs that cleared, and runs that died in the last room before the end. The
## rule is `ClearedFinalState`'s, kept so its reports stay comparable.
var _detail: bool = false

func _init() -> void:
	var comps := PartySpec.compositions()
	if comps.is_empty():
		printerr("no compositions to run")
		quit(1)
		return
	var arm := ArmArgs.apply()
	if arm.is_empty():
		quit(1)
		return
	_detail = OS.get_cmdline_user_args().has("--final-state")
	print("Floor runs, issue 730/734/808: arm A (default) vs arm B (planned), %d seeds." % SEEDS)
	print(arm)
	print(ReviveArgs.apply())
	print(LootArgs.apply())
	print("final state per run: %s\n" % (
		"ON, cleared runs and near misses" if _detail else "off (--final-state)"))
	for ids in comps:
		print("========================================================")
		print("PARTY OF %d: %s" % [ids.size(), PartySpec.label(ids)])
		print("========================================================")
		_report("Arm A -- default pawns, no plans", _run_arm(ids, false))
		_report("Arm B -- planned pawns", _run_arm(ids, true))
	quit(0)

func _run_arm(ids: Array, planned: bool) -> Dictionary:
	var cleared := 0
	var died_at := {}
	var depths: Array[int] = []
	var camp_unused := 0
	var drops := 0
	## Issue 822: the count alone cannot tell a working loot loop from four
	## no-op censers, which is what filling `off_hand` leaves droppable.
	var dropped := {}
	## Issue 814: survivor count is the only narrowness axis a clear has, so a
	## clear that has to be read as "by the skin of their teeth" is reported by
	## how many of the four are still standing, not only that it happened.
	var clear_survivors: Array[int] = []
	var detail: Array[String] = []
	for s in range(SEEDS):
		var plan := FloorGenerator.generate(s)
		var walk := FloorWalk.default_room_order(plan)
		var party := PartySpec.make(ids, planned)
		var run := FloorRun.new()
		var wiped := false
		var last_state: CombatState = null
		for i in walk.size():
			var room := plan.room(walk[i])
			var room_id: StringName = room.content_id
			var encounter := RoomScale.scaled(RoomLibrary.get_room(room_id), party.size())
			var state := CombatSim.build(party, encounter, hash([s, room_id, i]))
			last_state = state
			FloorRun.carry_into(run, state, party, i)
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
			## Issue 811: the room resolved, so it pays out -- the same call
			## BattleView._handle_fight_end makes on the live floor.
			FloorRun.award_room_loot(run, room, party, s)
		if not wiped:
			cleared += 1
			depths.append(walk.size())
			var standing := 0
			for j in party.size():
				if last_state.unit(j).alive:
					standing += 1
			clear_survivors.append(standing)
		if _detail:
			_final_state_lines(detail, s, party, last_state,
				depths[depths.size() - 1], walk.size(), wiped)
		drops += run.loot.size()
		for item in run.loot:
			dropped[item.id] = int(dropped.get(item.id, 0)) + 1
		if not run.revive_used:
			camp_unused += 1
	return {"cleared": cleared, "died_at": died_at, "depths": depths,
		"camp_unused": camp_unused, "drops": drops, "dropped": dropped, "party": ids.size(),
		"clear_survivors": clear_survivors, "detail": detail}

## Issue 817, and this is the whole of what `ClearedFinalState.gd` did. It reads
## off the loop above rather than off a second copy of it, so it sees the loot
## that loop awards, which is the one thing the deleted tool never did. The
## selection rule is that tool's, unchanged: a run that cleared, or one that
## died no earlier than the second-to-last room.
##
## Collected rather than printed, because `_run_arm` runs before `_report`
## prints the arm's heading, so printing from in here put arm B's runs under
## the words "Arm A".
func _final_state_lines(out: Array[String], seed_value: int, party: Array[PawnData],
		state: CombatState, depth: int, rooms: int, wiped: bool) -> void:
	if state == null or (wiped and depth < rooms - 1):
		return
	out.append("    seed %d %s (depth %d/%d):" % [
		seed_value, "died" if wiped else "CLEARED", depth, rooms])
	for j in party.size():
		var unit := state.unit(j)
		var pct := 0
		if unit.hp_max > 0:
			pct = int(round(100.0 * unit.hp / unit.hp_max))
		out.append("      %-14s %s  hp %d/%d (%d%%)" % [
			String(party[j].id), "alive" if unit.alive else "DEAD",
			unit.hp, unit.hp_max, pct])

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
	if FloorRun.REVIVE_ONCE_ON_TWO_DOWN:
		print("  the camp's one revive went unused in %d of %d runs (never two down)" % [
			r.camp_unused, SEEDS])
	## Issue 811: every drop is filtered to something a living pawn can put on,
	## so items found and items worn are the same number by construction.
	print("  loot: %d items found and worn across %d runs (%.2f a run)" % [
		r.drops, SEEDS, float(r.drops) / SEEDS])
	print("    what dropped: %s" % _dropped_line(r.dropped))
	_report_depth(r.depths, r.cleared)
	_report_survivors(r.clear_survivors, int(r.party))
	var detail: Array = r.detail
	if _detail:
		if detail.is_empty():
			print("  final state: no run cleared or came within one room of it")
		else:
			print("  final state of the runs that cleared or nearly did:")
			for line in detail:
				print(line)
	print("")

## Issue 822: which items the drops actually were. A loot line near baseline
## made of one no-op accessory is not a working loot loop, and the count alone
## reads the same in both cases.
func _dropped_line(dropped: Dictionary) -> String:
	if dropped.is_empty():
		return "nothing"
	var ids: Array = dropped.keys()
	ids.sort_custom(func(a, b): return dropped[a] > dropped[b] or \
		(dropped[a] == dropped[b] and String(a) < String(b)))
	var parts := PackedStringArray()
	for id in ids:
		parts.append("%s x%d" % [String(id), dropped[id]])
	return ", ".join(parts)

## Issue 814: #802 measured that a run cannot finish in the red while The
## Warden leaves an intact party at 93% health, so this is the only axis a
## "by the skin of their teeth" clear can be read on.
func _report_survivors(survivors: Array[int], party_size: int) -> void:
	if survivors.is_empty():
		return
	var histogram := {}
	for n in survivors:
		histogram[n] = int(histogram.get(n, 0)) + 1
	var line := "  the cleared runs finished with (of %d): " % party_size
	for n in range(party_size, -1, -1):
		if histogram.has(n):
			line += "%d alive x%d  " % [n, histogram[n]]
	print(line)

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
