extends SceneTree

## What share of the hostile shots that reach the party does the Warrior's plate
## take on the shield, on the fixture `Tests/test_content_equipment_grants.gd`
## uses. Reads `state.events` after `CombatSim.run`, so it never perturbs.

const SEEDS := 6
const ROOM := &"floor1_chokepoint"

func _init() -> void:
	for strip in [false, true]:
		var blocked := 0
		var enemy_shots := 0
		var casts := 0
		for s in SEEDS:
			var party: Array[PawnData] = []
			for cid in ClassLibrary.all_ids():
				var p := PawnFactory.make_preset_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid))
				if strip:
					p.body = null
				party.append(p)
			var state := CombatSim.build(party, RoomLibrary.get_room(ROOM), s)
			CombatSim.run(state)
			for e in state.events:
				if e.kind == CG.EventKind.BLOCKED:
					blocked += 1
				elif e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"warrior_block":
					casts += 1
				elif e.kind == CG.EventKind.ACTION_FIRE and e.source_id >= 0:
					var src := state.unit(e.source_id)
					if src != null and src.team == CG.Team.ENEMY:
						enemy_shots += 1
		print("strip_armor=%s casts=%d blocked=%d enemy_shots=%d share=%.4f" % [
			strip, casts, blocked, enemy_shots, float(blocked) / maxf(1.0, float(enemy_shots))])
	quit(0)
