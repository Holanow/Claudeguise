extends SceneTree

## Issue 793: does the Geysermancer's first plan row ever fire? The row
## "Blast the burning" leads the preset library, so a planned run either casts
## it or something below the row refuses it.

const SEEDS := 12

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	for planned in [false, true]:
		var fires := {}
		var burns := 0
		for s in range(SEEDS):
			var party: Array[PawnData] = []
			for cid in class_ids:
				var c := StringName(cid)
				var d := ClassLibrary.get_class_def(c).display_name
				party.append(PawnFactory.make_preset_pawn(c, c, d) if planned \
					else PawnFactory.make_starter_pawn(c, c, d))
			var run := FloorRun.new()
			var room_ids := FloorSequence.build(s)
			for i in room_ids.size():
				var rid: StringName = room_ids[i]
				var state := CombatSim.build(party, RoomLibrary.get_room(rid), hash([s, rid, i]))
				FloorRun.carry_into(run, state, party)
				CombatSim.run(state)
				for e in state.events:
					if e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.BURN:
						burns += 1
				var l := DamageLedger.build(state)
				for team in l.fires:
					for aid in l.fires[team]:
						fires[aid] = int(fires.get(aid, 0)) + l.fires[team][aid].count
				for j in party.size():
					var u := state.unit(j)
					run.record_result(party[j].id, u.hp, u.resource, u.alive)
				if state.outcome != CombatState.Outcome.PLAYER_WIN:
					break
		print("--- %s, %d seeds" % ["planned" if planned else "default", SEEDS])
		print("  BURN applications: %d" % burns)
		for aid in ["geyser_blast", "geyser_scald", "geyser_spout", "channel_mana", "geyser_cleanse"]:
			print("  %-18s %d" % [aid, int(fires.get(StringName(aid), 0))])
	quit(0)
