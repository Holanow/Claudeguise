extends SceneTree

## Every fight the balance tools measure, as one diffable line each.
##
##   godot --headless --path . --script res://Tools/OutcomeTable.gd > before.txt
##
## Written for issue 233, whose change ends a fight earlier than the old rule
## did. "Earlier" is only acceptable if it is also "same result", and the only
## way to know that is to take the whole table on both sides and diff it.


const SEEDS := 40

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	for encounter_id in Registry.all_encounter_ids():
		var encounter := Registry.get_encounter(encounter_id)
		for party_ids in _parties(class_ids):
			for s in SEEDS:
				var party: Array[PawnData] = []
				for cid in party_ids:
					party.append(PawnFactory.make_starter_pawn(
						cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
				var state := CombatSim.build(party, encounter, s)
				CombatSim.run(state)
				print("%s %s %d %s %d" % [
					encounter_id, "+".join(PackedStringArray(party_ids)), s,
					CombatState.Outcome.keys()[state.outcome], state.tick])
	quit(0)

func _parties(class_ids: Array) -> Array:
	var out := []
	if class_ids.size() > 4:
		for skip in class_ids.size():
			var party := []
			for i in class_ids.size():
				if i != skip:
					party.append(class_ids[i])
			out.append(party)
	elif class_ids.size() >= 1:
		out.append(class_ids.slice(0, mini(4, class_ids.size())))
	return out
