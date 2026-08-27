extends SceneTree

## Issue 433: whether a class's top library row ever fires, and what it fires
## instead when it does not. Samples the finished event stream, never live unit
## state, so it cannot perturb a fight.

const SEEDS := 20

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	var encounter_ids := Registry.pickable_encounter_ids()
	for cid in class_ids:
		_sample(cid, encounter_ids)
	quit(0)

## The `firstonly_<class>` arm of `Tools/PlanGap.gd`: one class carries its top
## library row alone, every other pawn is unedited.
func _sample(class_id: StringName, encounter_ids: Array) -> void:
	var preset := PawnFactory.make_preset_pawn(class_id, &"probe", String(class_id))
	if preset.plans.is_empty():
		print("%s: no library" % class_id)
		return
	var top: Plan = preset.plans[0]

	var by_plan := {}
	var by_action := {}
	var fights := 0
	var min_hp := 1.0
	for encounter_id in encounter_ids:
		var encounter := Registry.get_encounter(encounter_id)
		for party_ids in _parties(ClassLibrary.all_ids()):
			if not party_ids.has(class_id):
				continue
			for s in SEEDS:
				var party: Array[PawnData] = []
				for cid in party_ids:
					var pid := StringName("%s_%d" % [cid, party.size()])
					if cid == class_id:
						var p := PawnFactory.make_preset_pawn(cid, pid, String(cid))
						var one: Array[Plan] = [p.plans[0]]
						p.plans = one
						party.append(p)
					else:
						party.append(PawnFactory.make_starter_pawn(cid, pid, String(cid)))
				var state := CombatSim.build(party, encounter, s)
				while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
					min_hp = minf(min_hp, _lowest_seen(state, class_id))
					CombatSim.step(state)
				min_hp = minf(min_hp, _lowest_seen(state, class_id))
				fights += 1
				for e in state.events:
					if e.kind != CG.EventKind.ACTION_START:
						continue
					var u := state.unit(e.source_id)
					if u == null or u.pawn == null or u.pawn.pawn_class.id != class_id:
						continue
					var key: StringName = e.source_plan if e.source_plan != &"" else &"(fallback)"
					by_plan[key] = int(by_plan.get(key, 0)) + 1
					by_action[[key, e.action_id]] = int(by_action.get([key, e.action_id], 0)) + 1

	print("")
	print("======== %s: top row '%s' over %d fights ========" % [class_id, top.id, fights])
	print("  condition: %s" % (top.condition.describe() if top.condition != null else "always"))
	print("  lowest hp fraction this class ever reached: %.2f" % min_hp)
	var keys := by_plan.keys()
	keys.sort()
	for k in keys:
		print("  %-40s %d starts" % [k, by_plan[k]])
		for pair in by_action.keys():
			if pair[0] == k:
				print("      %-30s %d" % [pair[1], by_action[pair]])

## The lowest hp fraction any pawn of this class is on right now. Read before
## `step()` per ENGINEER.md, and reading hp writes nothing.
func _lowest_seen(state: CombatState, class_id: StringName) -> float:
	var lowest := 1.0
	for u in state.units:
		if u.pawn == null or u.pawn.pawn_class.id != class_id:
			continue
		lowest = minf(lowest, u.hp_fraction())
	return lowest

func _parties(class_ids: Array) -> Array:
	if class_ids.size() <= 4:
		return [class_ids.duplicate()]
	var out := []
	for skip in class_ids.size():
		var party := []
		for i in class_ids.size():
			if i != skip:
				party.append(class_ids[i])
		out.append(party)
	return out
