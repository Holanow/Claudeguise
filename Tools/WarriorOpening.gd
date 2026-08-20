extends SceneTree

## When does the Warrior first raise the Directional Block, and what does it
## cost the Warrior in ground?
##
##     godot --headless --path . --script res://Tools/WarriorOpening.gd
##
## `Tools/PillarStalkerLine.gd` shows the Warrior on #160 standing 76 units
## further back at tick 57 than on `main`, which is why the Stalker's 220-unit
## `stalker_mark` never reaches it and why the pillar that used to deny that one
## cast is never consulted. This prints the Warrior's first few casts and its
## position over the opening, so the delay can be attributed rather than
## assumed.
##
## Measurement only, not part of the gate.


const PARTY: Array[StringName] = [&"geysermancer", &"priest", &"siege_master", &"warrior"]
const SEEDS := 20


func _pawns(seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in PARTY.size():
		out.append(PawnFactory.make_starter_pawn(PARTY[i], StringName("%s_%d_%d" % [PARTY[i], seed, i]), String(PARTY[i])))
	return out


func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var state := CombatSim.build(_pawns(0), enc, 0)
	var warrior := -1
	for i in state.units.size():
		if state.units[i].display_name.findn("Warrior") >= 0:
			warrior = i
	CombatSim.run(state)
	print("seed 0, the Warrior's first 10 casts")
	var shown := 0
	for e in state.events:
		if e.source_id != warrior or String(e.action_id) == "":
			continue
		if e.kind != CG.EventKind.ACTION_START:
			continue
		print("  tick %-5d %s" % [e.tick, String(e.action_id)])
		shown += 1
		if shown >= 10:
			break

	var casts := 0
	var first_sum := 0
	var first_n := 0
	for seed in SEEDS:
		var st := CombatSim.build(_pawns(seed), enc, seed)
		CombatSim.run(st)
		var w := -1
		for i in st.units.size():
			if st.units[i].display_name.findn("Warrior") >= 0:
				w = i
		var first := -1
		for e in st.events:
			if e.source_id == w and e.action_id == &"warrior_block" and e.kind == CG.EventKind.ACTION_START:
				casts += 1
				if first < 0:
					first = e.tick
		if first >= 0:
			first_sum += first
			first_n += 1
	print("\nover %d seeds: %d block casts, first at mean tick %d in %d of them" % [
		SEEDS, casts, (first_sum / maxi(first_n, 1)), first_n,
	])
	quit()
