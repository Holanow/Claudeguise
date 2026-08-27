extends SceneTree

## Every event of a fixed set of fights, one line each, for hashing. Two runs of
## the same build must hash the same; two builds that differ in the simulation
## must not, which is what stops the hash from measuring nothing.

const SEEDS := 5

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	for encounter_id in Registry.all_encounter_ids():
		var encounter := Registry.get_encounter(encounter_id)
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
				CombatSim.run(state)
				print("== %s %s seed %d outcome %d ticks %d" % [
					encounter_id, ",".join(PackedStringArray(party_ids)), s, state.outcome, state.tick])
				for e in state.events:
					print("%d %d %d %d %s %d %d" % [
						e.tick, e.kind, e.source_id, e.target_id, e.action_id, e.status, e.amount])
	quit(0)
