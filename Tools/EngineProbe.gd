extends SceneTree
func _init() -> void:
	var ids := [&"abomination", &"priest", &"siege_master", &"warrior"]
	for maker in ["starter", "preset"]:
		var sm: PawnData = PawnFactory.make_starter_pawn(&"siege_master", &"sm", "SM") if maker == "starter" \
			else PawnFactory.make_preset_pawn(&"siege_master", &"sm", "SM")
		print("siege_master %s max_resource %d, start %d" % [
			maker, Balance.max_resource(sm),
			Balance.starting_resource(ClassLibrary.get_class_def(&"siege_master").resource_kind, Balance.max_resource(sm))])
	for planned in [false, true]:
		var fires := {}
		var census := {}
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
				## Sampled BEFORE the step, never after: a unit whose recover ends
				## inside the tick reads as free once `step` has returned.
				while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
					for u in state.units:
						if not u.alive or u.pawn == null or u.pawn.class_id != &"siege_master":
							continue
						if u.is_busy():
							census["busy"] = int(census.get("busy", 0)) + 1
							continue
						census["free"] = int(census.get("free", 0)) + 1
						if u.resource >= 40:
							census["free_and_rich"] = int(census.get("free_and_rich", 0)) + 1
							if _enemy_within(state, u, 350.0):
								census["free_rich_mark_wins"] = int(census.get("free_rich_mark_wins", 0)) + 1
					CombatSim.step(state)
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
		for k in ["busy", "free", "free_and_rich", "free_rich_mark_wins"]:
			print("  %-20s %d" % [k, int(census.get(k, 0))])
	quit(0)

## Whether the Mark row's condition holds, asked without calling `decide`.
static func _enemy_within(state: CombatState, unit: CombatUnit, reach: float) -> bool:
	for o in state.units:
		if o.alive and o.team != unit.team and o.pos.distance_to(unit.pos) <= reach:
			return true
	return false
