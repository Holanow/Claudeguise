extends SceneTree

## Issue 593: what the Warrior's block actually does, over PRESET parties.
##
##   godot --headless --path . --script res://Tools/BlockInFight.gd
##
## `Tools/SampleFights.gd` cannot see this ability at all and reads UNCHANGED
## across the whole issue. It builds starter pawns, a starter pawn carries no
## plan rows (issue 399), and `DefaultBehavior` gates `_self_targeted_to_cast`
## on `unit.pawn == null`, so no pawn has ever cast the block in that tool.
## This one deploys the authored library, which is what a player deploys.

const SEEDS := 8

func _init() -> void:
	var casts := 0
	var blocked := 0
	var soaked := 0
	var broken := 0
	var enemy_shots := 0
	var wins := 0
	var fights := 0
	for encounter_id in RoomLibrary.pickable_ids():
		var encounter := RoomLibrary.get_room(encounter_id)
		for s in SEEDS:
			var party: Array[PawnData] = []
			for cid in ClassLibrary.all_ids():
				party.append(PawnFactory.make_preset_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
			var state := CombatSim.build(party, encounter, s)
			var outcome := CombatSim.run(state)
			fights += 1
			if outcome == CombatState.Outcome.PLAYER_WIN:
				wins += 1
			for e in state.events:
				match e.kind:
					CG.EventKind.ACTION_FIRE:
						if e.action_id == &"warrior_block":
							casts += 1
						else:
							var src := state.unit(e.source_id)
							if src != null and src.team == CG.Team.ENEMY:
								enemy_shots += 1
					CG.EventKind.BLOCKED:
						blocked += 1
					CG.EventKind.SHIELD_ABSORBED:
						soaked += e.amount
					CG.EventKind.STATUS_EXPIRED:
						if e.status == CG.Status.SHIELDING:
							broken += 1
	print("BLOCK over %d fights (%d seeds x every room, preset parties)" % [fights, SEEDS])
	print("  raised          %d" % casts)
	print("  shots stopped   %d  of %d enemy actions" % [blocked, enemy_shots])
	print("  damage soaked   %d" % soaked)
	print("  shields broken  %d" % broken)
	print("  per raise       %.2f shots, %.1f damage" % [
		float(blocked) / maxf(1.0, float(casts)), float(soaked) / maxf(1.0, float(casts))])
	print("  party wins      %d / %d" % [wins, fights])
	quit(0)
