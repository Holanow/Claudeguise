extends SceneTree

## Where is the Warrior standing when the Stalker aims at it, and is a pillar in
## the way?
##
##     godot --headless --path . --script res://Tools/PillarStalkerLine.gd
##
## `Tools/PillarFirstDiff.gd` names the whole of the colonnade's early effect on
## `[geysermancer, priest, siege_master, warrior]`: on `main`, at tick 57, the
## Stalker casts `stalker_mark` on the Warrior in the bare room and **cannot**
## with the pillars in. Identical on every seed, so it is geometry rather than
## rolls. On #160 the fight is bit-identical between the two arms, so that
## denial has stopped happening.
##
## This traces the Stalker-to-Warrior line tick by tick to say which of the two
## it is: the Warrior standing somewhere else, or the pillar no longer counting.
##
## Measurement only, not part of the gate.


const PARTY: Array[StringName] = [&"geysermancer", &"priest", &"siege_master", &"warrior"]
const SEEDS := 20


func _pawns(seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in PARTY.size():
		out.append(PawnFactory.make_starter_pawn(PARTY[i], StringName("%s_%d_%d" % [PARTY[i], seed, i]), String(PARTY[i])))
	return out


func _find(state: CombatState, name_part: String) -> int:
	for i in state.units.size():
		if state.units[i].display_name.findn(name_part) >= 0:
			return i
	return -1


func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")

	# One seed, printed tick by tick, so the moment can be read directly.
	var state := CombatSim.build(_pawns(0), enc, 0)
	var stalker := _find(state, "Stalker")
	var warrior := _find(state, "Warrior")
	print("seed 0: stalker unit %d, warrior unit %d" % [stalker, warrior])
	print("tick   stalker pos            warrior pos            dist   line blocked")
	var tick := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and tick < 90:
		CombatSim.step(state)
		tick += 1
		if tick < 40:
			continue
		var s = state.units[stalker]
		var w = state.units[warrior]
		if not s.alive or not w.alive:
			print("%-6d one of them is dead" % tick)
			break
		print("%-6d %-22s %-22s %6.1f   %s" % [
			tick, str(s.position), str(w.position), s.position.distance_to(w.position),
			str(Terrain.line_is_blocked(state.terrain, s.position, w.position)),
		])

	# And across seeds, the summary: how many ticks of the whole fight is the
	# Stalker's line to the Warrior blocked by a pillar?
	print("\nover %d seeds: ticks in which a pillar stands between the Stalker and the Warrior" % SEEDS)
	var blocked_total := 0
	var live_total := 0
	for seed in SEEDS:
		var st := CombatSim.build(_pawns(seed), enc, seed)
		var si := _find(st, "Stalker")
		var wi := _find(st, "Warrior")
		while st.outcome == CombatState.Outcome.UNRESOLVED and st.tick < 3000:
			CombatSim.step(st)
			var s2 = st.units[si]
			var w2 = st.units[wi]
			if not s2.alive or not w2.alive:
				continue
			live_total += 1
			if Terrain.line_is_blocked(st.terrain, s2.position, w2.position):
				blocked_total += 1
	print("both alive for %d ticks, pillar between them in %d of them" % [live_total, blocked_total])
	quit()
