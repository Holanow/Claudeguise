extends SceneTree

## Issue 797: the same rooms fought by a SHRUNK party. Every floor-1 room is
## won 40/40 at full strength, so what ends a run is what the party has lost,
## not what a room is. This measures how much.

const SEEDS := 20

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	var ids := RoomLibrary.all_ids()
	ids.sort_custom(func(a, b): return String(a) < String(b))
	print("Win rate by surviving party size, %d seeds, full health.\n" % SEEDS)
	## Issue 808/814: this builds each column from the first N of
	## `ClassLibrary.all_ids()`, so its "4" is one composition of the five and
	## not four-in-general. It said so nowhere, which is the drift #808 was
	## about; naming the classes is the smallest thing that stops the number
	## being read as a statement about any four.
	for n in [5, 4, 3, 2]:
		print("  party of %d: %s" % [n, PartySpec.label(class_ids.slice(0, n))])
	print("")
	print("  %-24s  5     4     3     2" % "room")
	for rid in ids:
		var line := "  %-24s" % String(rid)
		for n in [5, 4, 3, 2]:
			var wins := 0
			for s in range(SEEDS):
				var party: Array[PawnData] = []
				for k in n:
					var c := StringName(class_ids[k])
					party.append(PawnFactory.make_preset_pawn(c, c, ClassLibrary.get_class_def(c).display_name))
				var state := CombatSim.build(party, RoomLibrary.get_room(StringName(rid)), hash([s, rid, n]))
				CombatSim.run(state)
				if state.outcome == CombatState.Outcome.PLAYER_WIN:
					wins += 1
			line += "  %3d%%" % int(round(100.0 * wins / SEEDS))
		print(line)
	quit(0)
