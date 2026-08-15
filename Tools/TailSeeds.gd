extends SceneTree

## Issue 233. Which seeds of `floor1_warden` x the offered party produce a
## pawnless tail, how long each tail is, and what stands in it.
##
##   godot --headless --path . --script res://Tools/TailSeeds.gd
##
## `PawnlessProbe` counts tails across every encounter. This names them, so a
## single one can be re-run on screen through the real controls and looked at.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const ENCOUNTER := &"floor1_warden"
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const SEEDS := 40

func _init() -> void:
	var encounter := Registry.get_encounter(ENCOUNTER)
	for s in SEEDS:
		var party: Array[PawnData] = []
		for cid in PARTY:
			party.append(PawnFactory.make_starter_pawn(
				StringName(cid), StringName("%s_%d" % [cid, party.size()]), String(cid)))
		var state := CombatSim.build(party, encounter, s)
		var last_pawn_death := -1
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			CombatSim.step(state)
			if last_pawn_death < 0 and _living_pawns(state) == 0:
				last_pawn_death = state.tick
		if last_pawn_death < 0 or state.tick - last_pawn_death <= 0:
			continue
		var survivors: Array[String] = []
		for u in state.units:
			if u.alive and u.team == CG.Team.PLAYER:
				survivors.append(String(u.enemy_id) if u.pawn == null else String(u.pawn.id))
		print("seed %d (%08X): last pawn died tick %d, fight ended tick %d, tail %d ticks (%.1fs), %s, survivors %s" % [
			s, s, last_pawn_death, state.tick, state.tick - last_pawn_death,
			float(state.tick - last_pawn_death) / float(CG.TICKS_PER_SECOND),
			CombatState.Outcome.keys()[state.outcome], str(survivors)])
	quit(0)

static func _living_pawns(state: CombatState) -> int:
	var n := 0
	for u in state.units:
		if u.alive and u.team == CG.Team.PLAYER and u.pawn != null:
			n += 1
	return n
