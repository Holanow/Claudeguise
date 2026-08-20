extends SceneTree

## How much headroom `Tests/test_content_cleanse.gd`'s fixture actually has,
## per encounter and per seed count.


const MAX_SEEDS := 24

func _init() -> void:
	print("")
	print("%-22s %6s %8s %8s %8s %9s %9s" % ["encounter", "seeds", "casts", "strips", "harmful", "on_ally", "poisonings"])
	for encounter_id in Registry.all_encounter_ids():
		for seeds in [6, 12, 24, 48]:
			var casts := 0
			var strips := 0
			var harmful := 0
			var on_ally := 0
			var poisonings := 0
			for s in seeds:
				var state := _run(encounter_id, s)
				for e in state.events:
					if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"geyser_cleanse":
						casts += 1
					elif e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.POISON:
						var t := state.unit(e.target_id)
						if t != null and t.team == CG.Team.PLAYER:
							poisonings += 1
					elif e.kind == CG.EventKind.STATUS_EXPIRED and e.source_id != -1 and e.action_id == &"geyser_cleanse":
						strips += 1
						if CG.is_harmful(e.status):
							harmful += 1
						if e.target_id != e.source_id:
							on_ally += 1
			print("%-22s %6d %8d %8d %8d %9d %9d%s%s" % [
				encounter_id, seeds, casts, strips, harmful, on_ally, poisonings,
				"   <- SUPPLY FAILS" if harmful == 0 else "",
				"   <- ON_ALLY AT RISK" if on_ally <= 2 else "",
			])
	quit(0)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in Registry.all_class_ids():
		if cid == &"abomination":
			continue
		out.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out

func _run(encounter_id: StringName, fight_seed: int) -> CombatState:
	var deps := SimDeps.new()
	var state := CombatSim.build(_party(), Registry.get_encounter(encounter_id), fight_seed, deps)
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state, deps)
	return state
