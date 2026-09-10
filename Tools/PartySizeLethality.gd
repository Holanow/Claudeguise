extends SceneTree

## Issue 797: the same rooms fought by a SHRUNK party, every composition of
## each size rather than the first n of the roster (issue 816).

const SEEDS := 20
const SIZES := [5, 4, 3, 2]

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	var ids := RoomLibrary.all_ids()
	ids.sort_custom(func(a, b): return String(a) < String(b))
	var parties := {}
	var counts := PackedStringArray()
	for n in SIZES:
		parties[n] = PartySpec._combinations(class_ids, n)
		counts.append("%d at %d" % [parties[n].size(), n])
	print("Win rate by surviving party size, %d seeds, full health." % SEEDS)
	print("Each cell is the mean over every composition of that size: %s.\n"
		% ", ".join(counts))
	print("  %-24s  5     4     3     2" % "room")
	for rid in ids:
		var line := "  %-24s" % String(rid)
		for n in SIZES:
			var wins := 0
			var fights := 0
			for party_ids in parties[n]:
				for s in range(SEEDS):
					var state := CombatSim.build(PartySpec.make(party_ids, true),
						RoomLibrary.get_room(StringName(rid)), hash([s, rid, n]))
					CombatSim.run(state)
					fights += 1
					if state.outcome == CombatState.Outcome.PLAYER_WIN:
						wins += 1
			line += "  %3d%%" % int(round(100.0 * wins / fights))
		print(line)
	quit(0)
