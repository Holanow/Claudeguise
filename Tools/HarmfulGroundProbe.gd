extends SceneTree

## Issue 420: who actually stands in the fire, and what the new movement op does
## about it.
##
## Samples positions BEFORE each step and never calls `decide`.

const _SEEDS := 24
const _PARTY := [&"warrior", &"priest", &"geysermancer", &"abomination"]

func _init() -> void:
	print("issue 420 -- Floor 1, The Burn Pit, %d seeds" % _SEEDS)
	for arm in [&"", &"keep_distance", &"leave_harmful_ground"]:
		var label := "no row" if arm == &"" else ("kite 210 (as filed)" if arm == &"keep_distance" else "leave harmful ground")
		var r := _sweep(arm)
		print("  %-22s  wins %2d/%d  ground dmg %5d  ticks %6d" % [
			label, r["wins"], _SEEDS, r["ground"], r["ticks"]])
		for cid in _PARTY:
			print("      %-14s alive %6d  on harm %5d  deaths %2d" % [
				cid, r["alive"][cid], r["harm"][cid], r["deaths"][cid]])
	quit(0)

func _sweep(movement_op: StringName) -> Dictionary:
	var alive := {}
	var harm := {}
	var deaths := {}
	for cid in _PARTY:
		alive[cid] = 0
		harm[cid] = 0
		deaths[cid] = 0
	var wins := 0
	var ground := 0
	var ticks := 0
	for seed_value in _SEEDS:
		var state := CombatSim.build(_party(movement_op), Registry.get_encounter(&"floor1_hazard"), seed_value)
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			for u in state.units:
				if not u.alive or u.pawn == null:
					continue
				var cid: StringName = u.pawn.pawn_class.id
				alive[cid] += 1
				if CombatSim.standing_harms(state, u.position):
					harm[cid] += 1
			CombatSim.step(state)
		ticks += state.tick
		if state.outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
		for u in state.units:
			if u.pawn != null and not u.alive:
				deaths[u.pawn.pawn_class.id] += 1
		for e in state.events:
			if e.kind == CG.EventKind.DAMAGE and e.source_id == -1:
				ground += e.amount
	return {"alive": alive, "harm": harm, "deaths": deaths, "wins": wins, "ground": ground, "ticks": ticks}

## Every pawn gets the same one row, so the arms differ by the movement op only.
func _party(movement_op: StringName) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in _PARTY.size():
		var cid: StringName = _PARTY[i]
		var pawn := PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, i]), String(cid))
		if movement_op != &"":
			pawn.plans = [_row(movement_op)]
		out.append(pawn)
	return out

func _row(movement_op: StringName) -> Plan:
	var condition := PlanBlock.new()
	condition.kind = PlanBlock.Kind.CONDITION
	condition.op = &"self_on_harmful_ground"
	var targeting := PlanBlock.new()
	targeting.kind = PlanBlock.Kind.TARGETING
	targeting.op = &"target_nearest_enemy"
	var movement := PlanBlock.new()
	movement.kind = PlanBlock.Kind.MOVEMENT
	movement.op = movement_op
	if movement_op == &"keep_distance":
		movement.args = {"range": 210.0}
	var p := Plan.new()
	p.id = &"off_the_fire"
	p.display_name = "Off the fire"
	p.condition = condition
	p.blocks = [targeting, movement]
	return p
