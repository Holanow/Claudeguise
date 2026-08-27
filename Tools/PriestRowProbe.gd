extends SceneTree

## Issue 565: does the Priest's top library row do anything, and is the test
## that watches it a detector or a coin?
##
## Two arms of the same five-class party in `floor1_room1`: nobody carrying a
## row, and the Priest alone carrying its top one. Fight length and end-of-fight
## party health per seed, the heals the row cast, and the health those heals
## actually moved -- which is the number the issue never had.

const SEEDS := 40

## Attribution: `source_plan` is set on ACTION_START and nothing else, so the
## last start of an action by a unit says which row its HEAL belongs to.
var _plan_of := {}

func _init() -> void:
	var no_row := _arm(false)
	var with_row := _arm(true)
	_report(no_row, with_row)
	quit(0)

func _party(with_row: bool) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		var pid := StringName("%s_%d" % [cid, party.size()])
		if not with_row or cid != &"priest":
			party.append(PawnFactory.make_starter_pawn(cid, pid, String(cid)))
			continue
		var pawn := PawnFactory.make_preset_pawn(cid, pid, String(cid))
		var one: Array[Plan] = [pawn.plans[0]]
		pawn.plans = one
		party.append(pawn)
	return party

func _hp_percent(state: CombatState) -> int:
	var h := 0
	var h_max := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER or u.pawn == null:
			continue
		h += maxi(0, u.hp)
		h_max += u.hp_max
	return 0 if h_max <= 0 else int(round(100.0 * float(h) / float(h_max)))

func _arm(with_row: bool) -> Dictionary:
	var ticks: Array[int] = []
	var health: Array[int] = []
	var wins := 0
	var by_row := 0
	var by_fallback := 0
	var healed_by_row := 0
	var healed_by_fallback := 0
	for s in SEEDS:
		var state := CombatSim.build(_party(with_row), Registry.get_encounter(CG.DEFAULT_ENCOUNTER), s)
		CombatSim.run(state)
		ticks.append(state.tick)
		health.append(_hp_percent(state))
		if state.outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
		_plan_of.clear()
		for e in state.events:
			if e.action_id != &"priest_heal":
				continue
			if e.kind == CG.EventKind.ACTION_START:
				_plan_of[e.source_id] = e.source_plan
			elif e.kind == CG.EventKind.HEAL:
				var plan: StringName = _plan_of.get(e.source_id, &"")
				if plan == &"":
					by_fallback += 1
					healed_by_fallback += e.amount
				else:
					by_row += 1
					healed_by_row += e.amount
	return {"ticks": ticks, "health": health, "wins": wins,
		"by_row": by_row, "by_fallback": by_fallback,
		"healed_by_row": healed_by_row, "healed_by_fallback": healed_by_fallback}

func _differences(a: Array, b: Array) -> int:
	var n := 0
	for i in a.size():
		if a[i] != b[i]:
			n += 1
	return n

func _report(no_row: Dictionary, with_row: Dictionary) -> void:
	print("PriestRowProbe: %d seeds, floor1_room1, five-class party" % SEEDS)
	print("  no row    wins %d, %d priest_heal landed by the fallback restoring %d health" % [
		no_row["wins"], no_row["by_fallback"], no_row["healed_by_fallback"]])
	print("  with row  wins %d, %d by the row restoring %d health, %d by the fallback restoring %d" % [
		with_row["wins"], with_row["by_row"], with_row["healed_by_row"],
		with_row["by_fallback"], with_row["healed_by_fallback"]])
	print("  fight length differs on %d of %d seeds" % [
		_differences(no_row["ticks"], with_row["ticks"]), SEEDS])
	var moved := _differences(no_row["health"], with_row["health"])
	print("  end-of-fight party health differs on %d of %d seeds" % [moved, SEEDS])
	var biggest := 0
	for i in SEEDS:
		biggest = maxi(biggest, absi(int(no_row["health"][i]) - int(with_row["health"][i])))
	print("  the largest such difference is %d percentage points" % biggest)
	for i in SEEDS:
		if no_row["health"][i] == with_row["health"][i] and no_row["ticks"][i] == with_row["ticks"][i]:
			continue
		print("    seed %2d  ticks %d -> %d  health %d%% -> %d%%" % [
			i, no_row["ticks"][i], with_row["ticks"][i], no_row["health"][i], with_row["health"][i]])
