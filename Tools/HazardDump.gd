extends SceneTree

## Dumps every event of every fight, field by field, so two builds can be
## diffed byte for byte. Issue 204's determinism proof.

const SEEDS := 8

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	for encounter_id in RoomLibrary.all_ids():
		var encounter := RoomLibrary.get_room(encounter_id)
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
				var head := "%s|%s|%d" % [encounter_id, ",".join(PackedStringArray(party_ids)), s]
				print("%s|OUTCOME|%d|%d" % [head, state.outcome, state.tick])
				for e in state.events:
					print("%s|%d|%d|%d|%d|%d|%d|%s|%d|%d|%s|%d|%d|%d" % [
						head, e.kind, e.tick, e.source_id, e.target_id,
						e.amount, e.amount_before_mitigation, e.action_id,
						e.damage_type, e.status, e.source_plan, e.end_reason,
						e.amount_after_mitigation, e.mitigation_cause,
					])
	quit(0)
