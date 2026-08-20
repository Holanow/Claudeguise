extends SceneTree

## Do the encounter tests' assertions measure what their names say?



func _party_of(class_id: StringName, count: int) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for i in count:
		party.append(PawnFactory.make_starter_pawn(class_id, &"%s_%d" % [class_id, i], "%s %d" % [class_id, i]))
	return party


func _mixed(ids: Array, seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(ids[i], StringName("%s_%d_%d" % [ids[i], seed, i]), String(ids[i])))
	return out


func _outcome_name(o: int) -> String:
	return CombatState.Outcome.keys()[o]


## The test's own predicate, copied so the audit runs the real thing.
func _differs(a: Dictionary, b: Dictionary) -> bool:
	if a["outcome"] != b["outcome"]:
		return true
	var longer := maxf(float(a["ticks"]), float(b["ticks"]))
	var shorter := minf(float(a["ticks"]), float(b["ticks"]))
	if shorter <= 0.0:
		return longer > 0.0
	return (longer / shorter) >= 1.2


func _run_mono(class_id: StringName, seed: int) -> Dictionary:
	var enc := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	var state := CombatSim.build(_party_of(class_id, 4), enc, seed)
	var outcome := CombatSim.run(state)
	return {"outcome": outcome, "ticks": state.tick}


func _probe_unresolved() -> void:
	print("PROBE 1: can `state.outcome` be UNRESOLVED after run()?")
	print("  `test_the_chokepoint_room_resolves_instead_of_drawing` counts exactly that.")

	# The healthy input the assertion is actually run on today.
	var chokepoint := Registry.get_encounter(&"floor1_chokepoint")
	var seen := {}
	for seed in 40:
		var s := CombatSim.build(_party_of(&"siege_master", 4), chokepoint, seed)
		CombatSim.run(s)
		var k := _outcome_name(s.outcome)
		seen[k] = int(seen.get(k, 0)) + 1
	print("  floor1_chokepoint, siege_master x4, 40 seeds: %s" % str(seen))

	# The input it exists to catch. finch reported a real stall on #252:
	# floor1_cover, this party, and a stall means the tick cap.
	var cover := Registry.get_encounter(&"floor1_cover")
	var stalls := 0
	var stall_outcomes := {}
	for seed in 6000:
		var s := CombatSim.build(_mixed([&"geysermancer", &"priest", &"siege_master", &"warrior"], seed), cover, seed)
		CombatSim.run(s)
		if s.tick < CG.MAX_TICKS:
			continue
		stalls += 1
		var k := _outcome_name(s.outcome)
		stall_outcomes[k] = int(stall_outcomes.get(k, 0)) + 1
	print("  floor1_cover, no-abomination party, 6000 seeds: %d fights reached the %d-tick cap" % [stalls, CG.MAX_TICKS])
	print("  and the outcome a REAL STALL produces is: %s" % str(stall_outcomes))
	print("  -> the chokepoint assertion counts UNRESOLVED. A stall is not UNRESOLVED.")


func _probe_differs() -> void:
	print("\nPROBE 2: does `_differs` measure the class, or the seed?")
	var classes: Array[StringName] = [&"abomination", &"geysermancer", &"priest", &"siege_master", &"warrior"]
	var seeds := 16

	# Cache every run once.
	var runs := {}
	for c in classes:
		for seed in seeds:
			runs["%s_%d" % [c, seed]] = _run_mono(c, seed)

	# The assertion's own shape: two different classes, the same seed.
	var cross := 0
	var cross_n := 0
	for i in classes.size():
		for j in range(i + 1, classes.size()):
			for seed in seeds:
				cross_n += 1
				if _differs(runs["%s_%d" % [classes[i], seed]], runs["%s_%d" % [classes[j], seed]]):
					cross += 1

	# The control nobody has run: the SAME class, two different seeds. If this
	# trips at a similar rate, `_differs` is a seed detector wearing a class
	# detector's name.
	var same := 0
	var same_n := 0
	for c in classes:
		for a in seeds:
			for b in range(a + 1, seeds):
				same_n += 1
				if _differs(runs["%s_%d" % [c, a]], runs["%s_%d" % [c, b]]):
					same += 1

	print("  two classes, same seed :  %4d of %4d pairs differ  (%.0f%%)" % [cross, cross_n, 100.0 * cross / cross_n])
	print("  SAME class, two seeds  :  %4d of %4d pairs differ  (%.0f%%)   <- the control" % [same, same_n, 100.0 * same / same_n])

	print("  per class, the same class against itself across seed pairs:")
	for c in classes:
		var d := 0
		var n := 0
		for a in seeds:
			for b in range(a + 1, seeds):
				n += 1
				if _differs(runs["%s_%d" % [c, a]], runs["%s_%d" % [c, b]]):
					d += 1
		print("    %-14s %3d of %3d  (%.0f%%)" % [c, d, n, 100.0 * d / n])

	print("  and the three seeds the assertions are pinned to:")
	for pair in [[&"geysermancer", &"warrior", 2], [&"geysermancer", &"priest", 14], [&"geysermancer", &"siege_master", 1]]:
		var a: Dictionary = runs["%s_%d" % [pair[0], pair[2]]]
		var b: Dictionary = runs["%s_%d" % [pair[1], pair[2]]]
		var over := 0
		for seed in seeds:
			if _differs(runs["%s_%d" % [pair[0], seed]], runs["%s_%d" % [pair[1], seed]]):
				over += 1
		print("    %-14s vs %-14s seed %2d: %s/%d vs %s/%d, differs -> %s   (this pair differs on %d of %d seeds)" % [
			pair[0], pair[1], pair[2],
			_outcome_name(a["outcome"]), a["ticks"], _outcome_name(b["outcome"]), b["ticks"],
			str(_differs(a, b)), over, seeds,
		])


func _init() -> void:
	_probe_unresolved()
	_probe_differs()
	quit()
