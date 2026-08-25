extends SceneTree

## Issue 575: which plan row wins, at which instants, and what a busy pawn
## could not answer.
##
## Samples BEFORE `step()` returns, and the counterfactual advances `state.tick`
## by one around the `decide` call and restores `unit.focus_id`.

const SEEDS := 8

var _lines := PackedStringArray()

func _say(line: String = "") -> void:
	_lines.append(line)
	print(line)

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()
	_say("classes: " + str(class_ids))
	_say("encounters: " + str(encounter_ids))

	_say("")
	_say("=== 0. HOW FAR AWAY THE NEAREST ENEMY IS AT SPAWN, EVERY ENCOUNTER ===")
	_spawn_distance_table(class_ids, encounter_ids)

	_say("")
	_say("=== 1. CAN EACH PRESET ROW'S CONDITION HOLD AT THE FIRST IDLE INSTANT? ===")
	_first_instant_table(class_ids, Registry.get_encounter(encounter_ids[0]))

	_say("")
	_say("=== 2. ROW WINS AND WHAT A BUSY PAWN COULD NOT READ ===")
	var totals := {}
	for encounter_id in encounter_ids:
		var encounter := Registry.get_encounter(encounter_id)
		for party_ids in _parties(class_ids):
			_accumulate(totals, _run_party(party_ids, encounter))
	_report(totals, "ALL ENCOUNTERS, ALL BUILDABLE PARTIES")

	_say("")
	_say("=== 3. GAPS BETWEEN THE INSTANTS A PLAN IS READ AT ALL ===")
	_gap_table(class_ids, encounter_ids)

	_say("")
	_say("=== 4. DOES PROBING PERTURB THE FIGHT? ===")
	_perturbation_check(class_ids, encounter_ids)

	_say("")
	_say("=== 5. THE #567 ARM: siege_master + warrior, default encounter ===")
	var arm := _run_party([&"siege_master", &"warrior"], Registry.get_encounter(CG.DEFAULT_ENCOUNTER))
	_report(arm, "siege_master + warrior")

	_say("")
	_say("=== 6. OF THE ACTIONS A PRESET PAWN ACTUALLY TAKES, HOW MANY DID A ROW CHOOSE? ===")
	_authorship_table(class_ids, encounter_ids)

	quit(0)

# ---------------------------------------------------------------------------

## Every buildable party: leave-one-out, so every class is in four of the five
## and none is dropped by its position in the roster. Issue 350.
func _parties(class_ids: Array) -> Array:
	var out := []
	for skip in class_ids.size():
		var party := []
		for i in class_ids.size():
			if i != skip:
				party.append(class_ids[i])
		out.append(party)
	return out

## The nearest enemy at tick 1, per encounter, over the whole buildable party --
## the number every proximity-gated row is measured against at its first instant.
func _spawn_distance_table(class_ids: Array, encounter_ids: Array) -> void:
	for eid in encounter_ids:
		var party: Array[PawnData] = []
		for cid in _parties(class_ids)[0]:
			party.append(PawnFactory.make_preset_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
		var state := CombatSim.build(party, Registry.get_encounter(eid), 0)
		var nearest := INF
		var farthest := 0.0
		for u in state.units:
			if u.pawn == null:
				continue
			var d := _nearest_enemy_distance(state, u)
			nearest = minf(nearest, d)
			farthest = maxf(farthest, d)
		_say("  %-20s nearest pawn-to-enemy %.0f, farthest %.0f" % [eid, nearest, farthest])

## For each class, each preset row, and the very first tick of a fight: does the
## row's CONDITION hold, and does the row produce an intent?
func _first_instant_table(class_ids: Array, encounter) -> void:
	var party: Array[PawnData] = []
	for cid in class_ids:
		party.append(PawnFactory.make_preset_pawn(cid, StringName("%s_solo" % cid), String(cid)))
	for pawn in party:
		var one: Array[PawnData] = [pawn]
		var state := CombatSim.build(one, encounter, 0)
		var unit := _pawn_unit(state, pawn)
		if unit == null:
			continue
		state.tick += 1
		var nearest := _nearest_enemy_distance(state, unit)
		_say("")
		_say("%s  (nearest enemy at spawn: %.0f units)" % [pawn.pawn_class.id, nearest])
		for i in unit.pawn.plans.size():
			var plan: Plan = unit.pawn.plans[i]
			var holds := PlanInterpreter.condition_holds(state, unit, plan)
			var fires := false
			if holds:
				var saved := unit.focus_id
				fires = _plan_intent(state, unit, plan) != null
				unit.focus_id = saved
			_say("  row %d  %-34s condition %-3s  produces an intent %s" % [
				i + 1, plan.display_name, "yes" if holds else "NO", "yes" if fires else "NO"])
		state.tick -= 1

## One row asked on its own: the condition, then the blocks, exactly the pair
## `PlanInterpreter.decide` applies. Reaches the private helper rather than
## widening the interpreter's interface, because the sim fingerprint hashes that
## file and this probe must not move it.
func _plan_intent(state: CombatState, unit: CombatUnit, plan: Plan) -> Intent:
	if not PlanInterpreter.condition_holds(state, unit, plan):
		return null
	return PlanInterpreter._run_blocks(state, unit, plan)

func _pawn_unit(state: CombatState, pawn: PawnData) -> CombatUnit:
	for u in state.units:
		if u.pawn == pawn:
			return u
	return null

func _nearest_enemy_distance(state: CombatState, unit: CombatUnit) -> float:
	var best := INF
	for u in state.living(CG.Team.ENEMY):
		best = minf(best, unit.position.distance_to(u.position))
	return best

# ---------------------------------------------------------------------------

## One party over `SEEDS` seeds. Returns the tally described in `_report`.
func _run_party(party_ids: Array, encounter) -> Dictionary:
	var t := {
		"free_ticks": 0,
		"busy_ticks": 0,
		"blocked_ticks": 0,
		"blocked_episodes": 0,
		"longest_block": 0,
		"row_wins": {},
		"blocked_rows": {},
		"gaps": [],
	}
	for s in SEEDS:
		var party: Array[PawnData] = []
		for cid in party_ids:
			party.append(PawnFactory.make_preset_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
		var state := CombatSim.build(party, encounter, s)
		## Which row each pawn is currently committed to, by unit id.
		var committed := {}
		## How many consecutive ticks each pawn has been unable to read a better
		## row, by unit id.
		var running := {}
		## Ticks since this pawn was last free, by unit id.
		var gap := {}
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			for unit in state.units:
				if not unit.alive or unit.pawn == null:
					continue
				if unit.has_status(CG.Status.STUN) or unit.has_status(CG.Status.TAUNTED):
					continue
				if unit.is_busy():
					t["busy_ticks"] += 1
					gap[unit.id] = int(gap.get(unit.id, 0)) + 1
					var want := _row_that_would_win(state, unit)
					var have: int = committed.get(unit.id, 9999)
					if want != -1 and want < have:
						t["blocked_ticks"] += 1
						_bump(t["blocked_rows"], _row_key(unit, want))
						var n: int = int(running.get(unit.id, 0)) + 1
						running[unit.id] = n
						if n == 1:
							t["blocked_episodes"] += 1
						t["longest_block"] = maxi(t["longest_block"], n)
					else:
						running[unit.id] = 0
				else:
					t["free_ticks"] += 1
					if int(running.get(unit.id, 0)) > 0 or int(gap.get(unit.id, 0)) > 0:
						(t["gaps"] as Array).append(int(gap.get(unit.id, 0)))
					gap[unit.id] = 0
					running[unit.id] = 0
					var won := _row_that_would_win(state, unit)
					committed[unit.id] = won if won != -1 else 9999
					_bump(t["row_wins"], _row_key(unit, won))
			CombatSim.step(state)
	return t

## The index of the row `PlanInterpreter` would pick right now, or -1 when no
## row does and `DefaultBehavior` would decide instead.
func _row_that_would_win(state: CombatState, unit: CombatUnit) -> int:
	var saved := unit.focus_id
	state.tick += 1
	var won := -1
	var active := PlanInterpreter.active_plan_count(unit.pawn)
	for i in active:
		if _plan_intent(state, unit, unit.pawn.plans[i]) != null:
			won = i
			break
	state.tick -= 1
	unit.focus_id = saved
	return won

func _row_key(unit: CombatUnit, row: int) -> String:
	if row == -1:
		return "%s / no row (DefaultBehavior)" % unit.pawn.pawn_class.id
	return "%s / row %d %s" % [unit.pawn.pawn_class.id, row + 1, unit.pawn.plans[row].display_name]

func _bump(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1

func _accumulate(into: Dictionary, from: Dictionary) -> void:
	for k in ["free_ticks", "busy_ticks", "blocked_ticks", "blocked_episodes"]:
		into[k] = int(into.get(k, 0)) + int(from[k])
	into["longest_block"] = maxi(int(into.get("longest_block", 0)), int(from["longest_block"]))
	var g: Array = into.get("gaps", [])
	g.append_array(from["gaps"])
	into["gaps"] = g
	for sub in ["row_wins", "blocked_rows"]:
		var dst: Dictionary = into.get(sub, {})
		for k in from[sub]:
			dst[k] = int(dst.get(k, 0)) + int(from[sub][k])
		into[sub] = dst

func _report(t: Dictionary, title: String) -> void:
	var free: int = int(t["free_ticks"])
	var busy: int = int(t["busy_ticks"])
	var blocked: int = int(t["blocked_ticks"])
	_say("")
	_say("-- %s" % title)
	_say("  pawn-ticks free %d, busy %d  (%.1f%% of a pawn's life is busy)" % [
		free, busy, 100.0 * float(busy) / maxf(1.0, float(free + busy))])
	_say("  busy ticks where a STRICTLY HIGHER row was ready and unreadable: %d  (%.1f%% of busy ticks)" % [
		blocked, 100.0 * float(blocked) / maxf(1.0, float(busy))])
	_say("  episodes %d, longest single block %d ticks" % [
		int(t["blocked_episodes"]), int(t["longest_block"])])
	_say("  rows that won a free tick:")
	for k in _sorted_keys(t["row_wins"]):
		_say("    %6d  %s" % [int(t["row_wins"][k]), k])
	_say("  rows that were ready and unreadable:")
	if t["blocked_rows"].is_empty():
		_say("    none")
	for k in _sorted_keys(t["blocked_rows"]):
		_say("    %6d  %s" % [int(t["blocked_rows"][k]), k])

func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	return keys

# ---------------------------------------------------------------------------

## How long a pawn goes between the instants its plan is read at all, per class.
func _gap_table(class_ids: Array, encounter_ids: Array) -> void:
	for cid in class_ids:
		var gaps: Array = []
		for eid in encounter_ids:
			var t := _run_party([cid, cid, cid, cid], Registry.get_encounter(eid))
			gaps.append_array(t["gaps"])
		if gaps.is_empty():
			continue
		gaps.sort()
		_say("  %-14s gaps %d   median %d ticks, 90th %d, max %d" % [
			cid, gaps.size(), gaps[gaps.size() / 2], gaps[int(gaps.size() * 0.9)], gaps[-1]])

## Every fight in section 2's first party, run once probed and once bare, then
## compared on the two things a perturbation would move. Prints the count that
## differ, and 0 is the only acceptable answer.
func _perturbation_check(class_ids: Array, encounter_ids: Array) -> void:
	var perturbed := 0
	var checked := 0
	for eid in encounter_ids:
		var encounter := Registry.get_encounter(eid)
		for party_ids in _parties(class_ids):
			for s in SEEDS:
				var a := _fight(party_ids, encounter, s, true)
				var b := _fight(party_ids, encounter, s, false)
				checked += 1
				if a != b:
					perturbed += 1
					_say("    PERTURBED %s %s seed %d: probed %s bare %s" % [eid, _short(party_ids), s, a, b])
	_say("  %d fights compared, %d perturbed" % [checked, perturbed])

## Issue 155 put the deciding layer's answer on `ACTION_START.source_plan`, so
## this reads the event stream of an unprobed fight and asks nothing.
func _authorship_table(class_ids: Array, encounter_ids: Array) -> void:
	var by_class := {}
	for eid in encounter_ids:
		var encounter := Registry.get_encounter(eid)
		for party_ids in _parties(class_ids):
			for s in SEEDS:
				var party: Array[PawnData] = []
				for cid in party_ids:
					party.append(PawnFactory.make_preset_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
				var state := CombatSim.build(party, encounter, s)
				while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
					CombatSim.step(state)
				for e in state.events:
					if e.kind != CG.EventKind.ACTION_START:
						continue
					var unit := state.unit(e.source_id)
					if unit == null or unit.pawn == null:
						continue
					var cid: StringName = unit.pawn.pawn_class.id
					var row: Dictionary = by_class.get(cid, {"row": 0, "fallback": 0})
					row["row" if e.source_plan != &"" else "fallback"] += 1
					by_class[cid] = row
	var rows := 0
	var fallback := 0
	for cid in by_class:
		var r: int = int(by_class[cid]["row"])
		var f: int = int(by_class[cid]["fallback"])
		rows += r
		fallback += f
		_say("  %-14s actions started %5d,  a plan row chose %5d (%.1f%%),  the fallback chose %5d" % [
			cid, r + f, r, 100.0 * float(r) / maxf(1.0, float(r + f)), f])
	_say("  %-14s actions started %5d,  a plan row chose %5d (%.1f%%),  the fallback chose %5d" % [
		"ALL", rows + fallback, rows, 100.0 * float(rows) / maxf(1.0, float(rows + fallback)), fallback])

func _short(ids: Array) -> String:
	var parts := PackedStringArray()
	for i in ids:
		parts.append(String(i))
	return ", ".join(parts)

## One fight, optionally probed exactly the way section 2 probes it. Returns the
## tick it ended on and its outcome, as a string to compare.
func _fight(party_ids: Array, encounter, seed_value: int, probed: bool) -> String:
	var party: Array[PawnData] = []
	for cid in party_ids:
		party.append(PawnFactory.make_preset_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
	var state := CombatSim.build(party, encounter, seed_value)
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		if probed:
			for unit in state.units:
				if not unit.alive or unit.pawn == null:
					continue
				if unit.has_status(CG.Status.STUN) or unit.has_status(CG.Status.TAUNTED):
					continue
				_row_that_would_win(state, unit)
		CombatSim.step(state)
	var hp := 0
	for u in state.units:
		hp += maxi(0, u.hp)
	return "tick %d outcome %d hp %d" % [state.tick, state.outcome, hp]
