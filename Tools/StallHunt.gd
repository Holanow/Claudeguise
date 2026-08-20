extends SceneTree

## Find a fight that still sits on the tick cap.
##
##     godot --headless --path . --script res://Tools/StallHunt.gd
##
## A guard whose counter is never exercised is worthless, so the stall test
## needs a known-bad input that stalls on a build with the fixes as well as
## without. Probe 2 checks the other half: if the seed does nothing for the
## party a guard samples, that guard's sample size is one whatever its loop
## says.
##
## **There is no stalling input left to find.** 8 rooms x 10 parties x 500
## seeds = 40,000 fights, 0 on the cap; longest was 2,338 ticks, 65% of the
## cap, and only 2 fights got past half of it. That is why the stall test
## builds its fixture instead of pinning one. Re-run this before assuming
## otherwise.
##
## Measurement only, never gated.
const ENCOUNTERS: Array[StringName] = [
	&"floor1_room1", &"floor1_chokepoint", &"floor1_cover", &"floor1_hazard",
	&"floor1_horde", &"floor1_ghoul_den", &"floor1_warden", &"floor1_rat_king",
]
const CLASSES: Array[StringName] = [
	&"abomination", &"geysermancer", &"priest", &"siege_master", &"warrior",
]


func _mixed(ids: Array, seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(ids[i], StringName("%s_%d_%d" % [ids[i], seed, i]), String(ids[i])))
	return out


func _mono(class_id: StringName, seed: int) -> Array[PawnData]:
	return _mixed([class_id, class_id, class_id, class_id], seed)


func _outcome_name(o: int) -> String:
	return CombatState.Outcome.keys()[o]


## Every mono party, plus the five real four-of-five comps, against every room.
func _parties() -> Array:
	var out := []
	for c in CLASSES:
		out.append({"name": String(c) + " x4", "ids": [c, c, c, c]})
	for missing in CLASSES:
		var ids := []
		for c in CLASSES:
			if c != missing:
				ids.append(c)
		out.append({"name": "no_" + String(missing), "ids": ids})
	return out


func _hunt(seeds: int) -> void:
	print("PROBE 1: which (room, party, seed) still reaches the %d-tick cap? %d seeds each." % [CG.MAX_TICKS, seeds])
	var parties := _parties()
	var fights := 0
	var stalls := 0
	for enc_id in ENCOUNTERS:
		var enc := Registry.get_encounter(enc_id)
		if enc == null:
			print("  %s: not in the registry" % enc_id)
			continue
		for p in parties:
			for seed in seeds:
				var state := CombatSim.build(_mixed(p["ids"], seed), enc, seed)
				CombatSim.run(state)
				fights += 1
				if state.tick < CG.MAX_TICKS:
					continue
				stalls += 1
				print("  STALL  %-18s %-16s seed %4d  ->  %s at tick %d" % [
					enc_id, p["name"], seed, _outcome_name(state.outcome), state.tick,
				])
	print("  %d fights, %d on the cap." % [fights, stalls])


## Does the seed change the fight the chokepoint guard samples?
func _seed_sensitivity() -> void:
	print("\nPROBE 2: does the seed do anything for the party the chokepoint guard runs?")
	for enc_id in [&"floor1_chokepoint", &"floor1_cover", &"floor1_room1"]:
		var enc := Registry.get_encounter(enc_id)
		for class_id in CLASSES:
			var ticks := {}
			for seed in 20:
				var state := CombatSim.build(_mono(class_id, seed), enc, seed)
				CombatSim.run(state)
				var k := "%s@%d" % [_outcome_name(state.outcome), state.tick]
				ticks[k] = int(ticks.get(k, 0)) + 1
			print("  %-18s %-14s x4, 20 seeds -> %d distinct results %s" % [
				enc_id, class_id, ticks.size(), str(ticks),
			])


func _init() -> void:
	_hunt(60)
	_seed_sensitivity()
	quit()
