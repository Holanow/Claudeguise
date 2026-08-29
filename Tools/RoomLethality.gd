extends SceneTree

## Issue 797: each floor-1 room fought on its own, by a full-health preset
## party, so a room's own difficulty is separated from the damage a run
## carries into it. FloorRuns reports where runs die; this reports what each
## room does to a party that arrives intact.

const SEEDS := 40

func _init() -> void:
	var comps := PartySpec.compositions()
	if comps.is_empty():
		printerr("no compositions to run")
		quit(1)
		return
	print("Room lethality, %d seeds, full-health preset party.\n" % SEEDS)
	for party_ids in comps:
		print("PARTY OF %d: %s" % [party_ids.size(), PartySpec.label(party_ids)])
		_composition(party_ids)
		print("")
	quit(0)

func _composition(party_ids: Array) -> void:
	var ids := RoomLibrary.all_ids()
	ids.sort_custom(func(a, b): return String(a) < String(b))
	for rid in ids:
		var wins := 0
		var hp_left := 0.0
		var deaths := 0
		for s in range(SEEDS):
			var party := PartySpec.make(party_ids, true)
			var state := CombatSim.build(party, RoomLibrary.get_room(StringName(rid)), hash([s, rid]))
			CombatSim.run(state)
			if state.outcome == CombatState.Outcome.PLAYER_WIN:
				wins += 1
			var frac := 0.0
			for j in party.size():
				var u := state.unit(j)
				if not u.alive:
					deaths += 1
				else:
					frac += float(u.hp) / float(u.hp_max)
			hp_left += frac / float(party.size())
		print("  %-24s win %2d/%d (%3d%%)   party hp left %3d%%   deaths %.1f/fight" \
			% [String(rid), wins, SEEDS, int(round(100.0 * wins / SEEDS)),
			int(round(100.0 * hp_left / SEEDS)), float(deaths) / SEEDS])
