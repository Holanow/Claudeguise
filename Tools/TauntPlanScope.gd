extends SceneTree

## Issue 379: how many pawn decision-ticks the taunt compulsion takes away from
## the plan layer, and what the plans would have done on those ticks.

const SEEDS := 20

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var deps := SimDeps.new()
	var totals := {}
	for encounter_id in Registry.all_encounter_ids():
		var encounter := Registry.get_encounter(encounter_id)
		var row := _measure(class_ids, encounter, deps)
		_print_row(String(encounter_id), row)
		for k in row:
			totals[k] = int(totals.get(k, 0)) + int(row[k])
	print("")
	print("========================================================")
	_print_row("ALL ENCOUNTERS", totals)
	quit(0)

func _measure(class_ids: Array, encounter, deps: SimDeps) -> Dictionary:
	var row := {
		"fights": 0,
		"free": 0,
		"compelled": 0,
		"plan_would_fire": 0,
		"plan_differs": 0,
		"plan_not_an_attack": 0,
		"compelled_move": 0,
		"probe_perturbed": 0,
		"fire_while_compelled_move": 0,
		"differs_in_target_only": 0,
		"plan_is_a_move": 0,
		"plan_attacks_someone_else": 0,
	}
	for skip in class_ids.size():
		var party_ids := []
		for i in class_ids.size():
			if i != skip:
				party_ids.append(class_ids[i])
		for s in SEEDS:
			var party: Array[PawnData] = []
			for cid in party_ids:
				party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
			var state := CombatSim.build(party, encounter, s)
			row["fights"] = int(row["fights"]) + 1
			_run_probed(state, deps, row)
			var clean: Array[PawnData] = []
			for cid in party_ids:
				clean.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, clean.size()]), String(cid)))
			var ref_state := CombatSim.build(clean, encounter, s)
			CombatSim.run(ref_state)
			if ref_state.tick != state.tick or ref_state.outcome != state.outcome or ref_state.events.size() != state.events.size():
				row["probe_perturbed"] = int(row.get("probe_perturbed", 0)) + 1
	return row

## Steps the fight by hand and samples every unit BEFORE `step()` runs, which is
## the only point at which the state matches what `_decide_phase` will see.
func _run_probed(state: CombatState, deps: SimDeps, row: Dictionary) -> void:
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		for unit in state.units:
			if not unit.alive or unit.pawn == null:
				continue
			if unit.has_status(CG.Status.STUN):
				continue
			if unit.intent != null or unit.is_busy():
				continue
			row["free"] = int(row["free"]) + 1
			if not unit.has_status(CG.Status.TAUNTED):
				continue
			var taunter := state.unit(int(unit.status_magnitude.get(CG.Status.TAUNTED, -1.0)))
			if taunter == null or not taunter.alive:
				continue
			row["compelled"] = int(row["compelled"]) + 1
			_counterfactual(state, unit, taunter, deps, row)
		CombatSim.step(state, deps)

## What the plan layer would have returned on a tick the compulsion took. The
## tick is advanced first because `_decide_phase` runs after `state.tick += 1`
## and cooldown readiness is compared against it.
func _counterfactual(state: CombatState, unit: CombatUnit, taunter: CombatUnit, deps: SimDeps, row: Dictionary) -> void:
	var compelled: Intent = CombatSim._compelled_intent(unit, taunter, deps)
	if compelled != null and compelled.kind == CG.IntentKind.MOVE_TO:
		row["compelled_move"] = int(row["compelled_move"]) + 1
	var saved_focus := unit.focus_id
	state.tick += 1
	var planned: Intent = PlanInterpreter.decide(state, unit)
	state.tick -= 1
	unit.focus_id = saved_focus
	if planned == null:
		return
	row["plan_would_fire"] = int(row["plan_would_fire"]) + 1
	if compelled == null or planned.kind != compelled.kind or planned.action_id != compelled.action_id or planned.target_id != compelled.target_id:
		row["plan_differs"] = int(row["plan_differs"]) + 1
	if compelled != null and compelled.kind == CG.IntentKind.MOVE_TO:
		row["fire_while_compelled_move"] = int(row.get("fire_while_compelled_move", 0)) + 1
	if compelled != null and compelled.kind == CG.IntentKind.USE_ACTION and planned.kind == CG.IntentKind.USE_ACTION and planned.action_id == compelled.action_id:
		row["differs_in_target_only"] = int(row.get("differs_in_target_only", 0)) + 1
	if planned.kind == CG.IntentKind.MOVE_TO:
		row["plan_is_a_move"] = int(row.get("plan_is_a_move", 0)) + 1
	elif planned.kind == CG.IntentKind.USE_ACTION:
		var a: ActionDef = Registry.get_action(planned.action_id)
		if a != null and a.heals:
			row["plan_not_an_attack"] = int(row["plan_not_an_attack"]) + 1
		elif planned.target_id != taunter.id:
			row["plan_attacks_someone_else"] = int(row.get("plan_attacks_someone_else", 0)) + 1

func _print_row(label: String, row: Dictionary) -> void:
	var free := maxf(1.0, float(row.get("free", 0)))
	var compelled := maxf(1.0, float(row.get("compelled", 0)))
	print("")
	print("%s  (%d fights)" % [label, int(row.get("fights", 0))])
	print("  pawn free-decide ticks                 %d" % int(row.get("free", 0)))
	print("  of those, plans unreachable (taunted)  %d (%.2f%%)" % [
		int(row.get("compelled", 0)), 100.0 * float(row.get("compelled", 0)) / free,
	])
	print("  of those, a plan row WOULD have fired  %d (%.0f%%)" % [
		int(row.get("plan_would_fire", 0)), 100.0 * float(row.get("plan_would_fire", 0)) / compelled,
	])
	print("  of those, it differs from the compulsion  %d" % int(row.get("plan_differs", 0)))
	print("  of those, the plan row is a heal          %d" % int(row.get("plan_not_an_attack", 0)))
	print("  compulsion produced a MOVE, not an attack %d" % int(row.get("compelled_move", 0)))
	print("      the plan row is a MOVE                %d" % int(row.get("plan_is_a_move", 0)))
	print("      the plan row attacks a DIFFERENT foe  %d" % int(row.get("plan_attacks_someone_else", 0)))
	print("      same action, different target only    %d" % int(row.get("differs_in_target_only", 0)))
	print("      fired while the compulsion was MOVING %d" % int(row.get("fire_while_compelled_move", 0)))
	print("  fights the probe perturbed                %d  (must be 0)" % int(row.get("probe_perturbed", 0)))
