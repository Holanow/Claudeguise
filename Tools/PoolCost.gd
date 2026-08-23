extends SceneTree

## Issue 492, throwaway: where the time goes. Wall clock and mean ticks for the
## same fights, so "slower per tick" and "more ticks" can be told apart.

const SEEDS := 10

func _init() -> void:
	for encounter_id in [&"floor1_room1", &"floor1_hazard"]:
		var encounter := Registry.get_encounter(encounter_id)
		var start := Time.get_ticks_msec()
		var ticks := 0
		var capped := 0
		var peak := 0
		for s in SEEDS:
			var party: Array[PawnData] = []
			for cid in [&"warrior", &"priest", &"geysermancer", &"siege_master"]:
				party.append(PawnFactory.make_preset_pawn(
					cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
			var state := CombatSim.build(party, encounter, s)
			CombatSim.run(state)
			ticks += state.tick
			peak = maxi(peak, state.terrain.size())
			if state.tick >= CG.MAX_TICKS:
				capped += 1
		print("%-16s %d fights: %6d ms, mean ticks %5.0f, hit the cap %d/%d, peak terrain %d" % [
			encounter_id, SEEDS, Time.get_ticks_msec() - start,
			float(ticks) / float(SEEDS), capped, SEEDS, peak])
	quit(0)
