extends SceneTree
func _init() -> void:
	var ids := [&"abomination", &"priest", &"siege_master", &"warrior"]
	for planned in [false, true]:
		var fires := {}
		for s in range(12):
			var party: Array[PawnData] = []
			for cid in ids:
				party.append(PawnFactory.make_preset_pawn(cid, cid, ClassLibrary.get_class_def(cid).display_name) if planned \
					else PawnFactory.make_starter_pawn(cid, cid, ClassLibrary.get_class_def(cid).display_name))
			var plan := FloorGenerator.generate(s)
			var run := FloorRun.new()
			var order := FloorWalk.default_room_order(plan)
			for i in order.size():
				var room := plan.room(order[i])
				var state := CombatSim.build(party, RoomScale.scaled(RoomLibrary.get_room(room.content_id), party.size()), hash([s, room.content_id]))
				FloorRun.carry_into(run, state, party, i)
				CombatSim.run(state)
				var l := DamageLedger.build(state)
				for team in l.fires:
					for aid in l.fires[team]:
						fires[aid] = int(fires.get(aid, 0)) + l.fires[team][aid].count
				for j in party.size():
					var u := state.unit(j)
					run.record_result(party[j].id, u.hp, u.resource, u.alive)
				if state.outcome != CombatState.Outcome.PLAYER_WIN:
					break
		print("--- %s, 12 seeds" % ["planned" if planned else "default"])
		for aid in ["build_siege_engine", "spotter_mark", "siege_master_shot", "siege_engine_bolt"]:
			print("  %-20s %d" % [aid, int(fires.get(StringName(aid), 0))])
	quit(0)
