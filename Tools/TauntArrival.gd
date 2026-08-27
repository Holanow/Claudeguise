extends SceneTree

## Issue 310: does the geometry permit a taunted pawn to arrive at all?
##
## Samples at the TOP of a tick, before `CombatSim.step()`, which is the state
## the compulsion's `_decide_phase` reads for that tick.

const SEEDS := 20
const ROOM := &"floor1_hazard"

## TAUNTED applications seen, to reconcile against #310's 235.
var applications := 0
var perturbed := 0

func _init() -> void:
	var deps := SimDeps.new()
	var enc := RoomLibrary.get_room(ROOM)
	var class_ids := ClassLibrary.all_ids()

	var windows: Array = []
	applications = 0
	perturbed = 0
	for skip in class_ids.size():
		var party_ids := []
		for i in class_ids.size():
			if i != skip:
				party_ids.append(class_ids[i])
		for s in SEEDS:
			var party: Array[PawnData] = []
			for cid in party_ids:
				party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
			var state := CombatSim.build(party, enc, s, deps)
			_run_probed(state, deps, windows)

			var clean: Array[PawnData] = []
			for cid in party_ids:
				clean.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, clean.size()]), String(cid)))
			var plain := CombatSim.build(clean, enc, s, deps)
			CombatSim.run(plain, deps)
			if plain.tick != state.tick or plain.outcome != state.outcome or plain.events.size() != state.events.size():
				perturbed += 1

	_report(windows)
	quit(0)

func _run_probed(state: CombatState, deps: SimDeps, windows: Array) -> void:
	var open := {}
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		var seen := {}
		for u in state.units:
			if not u.alive or not u.has_status(CG.Status.TAUNTED):
				continue
			var taunter := state.unit(int(u.status_magnitude.get(CG.Status.TAUNTED, -1.0)))
			if taunter == null or not taunter.alive:
				continue
			seen[u.id] = true
			var w
			if open.has(u.id):
				w = open[u.id]
			else:
				w = _open_window(state, u, taunter, deps)
				open[u.id] = w
				windows.append(w)
			_sample(u, taunter, w)
		for uid in open.keys():
			if not seen.has(uid):
				open[uid]["end"] = _end_reason(state, int(uid), open[uid])
				open.erase(uid)
		var before := {}
		for u in state.units:
			before[u.id] = u.position
		var events_before := state.events.size()
		CombatSim.step(state)
		for i in range(events_before, state.events.size()):
			var e: CombatEvent = state.events[i]
			if e.kind == CG.EventKind.ACTION_START and e.source_plan == Intent.COMPELLED and open.has(e.source_id):
				open[e.source_id]["swings"] += 1
		for uid in open:
			var u := state.unit(int(uid))
			if u != null and u.position != before[u.id]:
				open[uid]["moved"] += 1
	for uid in open:
		open[uid]["end"] = "fight over"
	for e in state.events:
		if e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.TAUNTED:
			applications += 1

## Why the compulsion stopped, read from the state the tick after it stopped.
func _end_reason(state: CombatState, uid: int, w: Dictionary) -> String:
	var u := state.unit(uid)
	if u == null or not u.alive:
		return "victim died"
	var taunter := state.unit(int(w["taunter"]))
	if taunter == null or not taunter.alive:
		return "taunter died"
	if not u.has_status(CG.Status.TAUNTED):
		return "expired" if state.tick >= int(w["expire_tick"]) else "cleansed early"
	return "other"

## Everything the compulsion has to work with on its first decide tick.
func _open_window(state: CombatState, u: CombatUnit, taunter: CombatUnit, deps: SimDeps) -> Dictionary:
	var defs: Array[ActionDef] = []
	for id in u.actions:
		var a: ActionDef = deps.action_lookup.call(id)
		if a != null:
			defs.append(a)
	var melee: ActionDef = DefaultBehavior.default_attack_action(defs, false)
	var ranged: ActionDef = DefaultBehavior.default_attack_action(defs, true)
	var reach := 0.0
	for a in [melee, ranged]:
		if a != null:
			reach = maxf(reach, a.range_units)
	var d0 := u.position.distance_to(taunter.position)
	var budget := int(u.statuses[CG.Status.TAUNTED]) - state.tick
	var speed := u.move_speed
	return {
		"d0": d0,
		"reach": reach,
		"speed": speed,
		"budget": budget,
		"need": int(ceil(maxf(0.0, d0 - reach) / maxf(0.001, speed))),
		"ticks": 0,
		"busy": 0,
		"moved": 0,
		"in_reach": 0,
		"latency": -1,
		"swings": 0,
		"min_dist": d0,
		"taunter": taunter.id,
		"team": u.team,
		"end": "",
		"expire_tick": int(u.statuses[CG.Status.TAUNTED]),
	}

func _sample(u: CombatUnit, taunter: CombatUnit, w: Dictionary) -> void:
	var d := u.position.distance_to(taunter.position)
	w["ticks"] += 1
	w["min_dist"] = minf(float(w["min_dist"]), d)
	if u.is_busy():
		w["busy"] += 1
	if d <= float(w["reach"]):
		if int(w["in_reach"]) == 0:
			w["latency"] = int(w["ticks"])
		w["in_reach"] += 1

func _report(windows: Array) -> void:
	var n := windows.size()
	var impossible := 0
	var never := 0
	var never_impossible := 0
	var never_possible := 0
	var busy_of_never := 0
	var ticks_of_never := 0
	var slack := 0.0
	for w in windows:
		var arrived: bool = int(w["in_reach"]) > 0
		var geometry_fails: bool = int(w["need"]) > int(w["budget"])
		if geometry_fails:
			impossible += 1
		if not arrived:
			never += 1
			ticks_of_never += int(w["ticks"])
			busy_of_never += int(w["busy"])
			if geometry_fails:
				never_impossible += 1
			else:
				never_possible += 1
				slack += float(int(w["budget"]) - int(w["need"]))

	print("")
	print("== ISSUE 310: taunt arrival, %s ==" % ROOM)
	print("  %d fights perturbed by the probe (re-run unprobed, tick/outcome/event count compared)" % perturbed)
	print("  TAUNTED applications %d, windows probed %d (a window opens the tick AFTER the application)" % [applications, n])
	print("  geometry cannot permit arrival (need > budget)   %d (%.0f%%)" % [impossible, 100.0 * float(impossible) / maxf(1.0, float(n))])
	print("  never got inside its own attack reach            %d (%.0f%%)" % [never, 100.0 * float(never) / maxf(1.0, float(n))])
	print("    of those, geometry never permitted it          %d" % never_impossible)
	print("    of those, geometry DID permit it               %d" % never_possible)
	if never_possible > 0:
		print("      mean spare ticks those had                  %.1f" % (slack / float(never_possible)))
	print("  ticks inside a never-arriving window             %d, of which busy %d (%.0f%%)" % [
		ticks_of_never, busy_of_never, 100.0 * float(busy_of_never) / maxf(1.0, float(ticks_of_never))])

	var by_end := {}
	for w in windows:
		var k: String = ("pawn " if int(w["team"]) == 0 else "enemy ") + str(w["end"]) + ("" if int(w["in_reach"]) > 0 else "  (never arrived)")
		by_end[k] = int(by_end.get(k, 0)) + 1
	var lat := 0.0
	var need_sum := 0.0
	var arrived_n := 0
	var slower := 0
	for w in windows:
		if int(w["in_reach"]) == 0:
			continue
		arrived_n += 1
		lat += float(w["latency"])
		need_sum += float(w["need"])
		if int(w["latency"]) > int(w["need"]) + 4:
			slower += 1
	print("")
	print("  of the %d that DID arrive: mean %.1f ticks taken against %.1f needed; %d took more than need+4" % [
		arrived_n, lat / maxf(1.0, float(arrived_n)), need_sum / maxf(1.0, float(arrived_n)), slower])

	var all_ticks := 0
	var all_busy := 0
	var all_reach := 0
	var all_moved := 0
	for w in windows:
		all_ticks += int(w["ticks"])
		all_busy += int(w["busy"])
		all_reach += int(w["in_reach"])
		all_moved += int(w["moved"])
	print("  taunted ticks %d: busy %d (%.0f%%), displaced %d (%.0f%%), already inside reach %d (%.0f%%)" % [
		all_ticks, all_busy, 100.0 * float(all_busy) / maxf(1.0, float(all_ticks)),
		all_moved, 100.0 * float(all_moved) / maxf(1.0, float(all_ticks)),
		all_reach, 100.0 * float(all_reach) / maxf(1.0, float(all_ticks))])

	var reached_no_swing := 0
	var swung := 0
	for w in windows:
		if int(w["swings"]) > 0:
			swung += 1
		elif int(w["in_reach"]) > 0:
			reached_no_swing += 1
	print("  landed at least one compelled ACTION_START             %d" % swung)
	print("  got inside reach and still never swung                 %d" % reached_no_swing)

	print("")
	print("  how the window ended:")
	var ks := by_end.keys()
	ks.sort()
	for k in ks:
		print("    %-30s %d" % [k, int(by_end[k])])

	print("")
	print("  %-6s %-8s %-7s %-7s %-6s %-6s %-6s %s" % ["d0", "reach", "speed", "need", "budget", "ticks", "busy", "ended by"])
	var shown := 0
	for w in windows:
		if int(w["in_reach"]) > 0:
			continue
		shown += 1
		if shown > 25:
			break
		print("  %-6.0f %-8.0f %-7.1f %-7d %-6d %-6d %-6d %s" % [
			w["d0"], w["reach"], w["speed"], w["need"], w["budget"], w["ticks"], w["busy"], w["end"]])
