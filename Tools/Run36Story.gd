extends SceneTree

## Issue 748: the material the recorded run's commentary is written from.

func _init() -> void:
	var ids := [&"abomination", &"priest", &"siege_master", &"warrior"]
	var party: Array[PawnData] = []
	for cid in ids:
		party.append(PawnFactory.make_preset_pawn(cid, cid, ClassLibrary.get_class_def(cid).display_name))
	var plan := FloorGenerator.generate(36)
	var run := FloorRun.new()
	var order := FloorWalk.default_room_order(plan)
	for i in order.size():
		var room := plan.room(order[i])
		var state := CombatSim.build(party, RoomScale.scaled(RoomLibrary.get_room(room.content_id), party.size()), hash([36, room.content_id]))
		var before := {}
		for j in party.size():
			before[party[j].id] = run.is_alive(party[j].id)
		FloorRun.carry_into(run, state, party, i)
		var revived: Array[String] = []
		for j in party.size():
			if not before[party[j].id] and state.unit(j).alive:
				revived.append(String(party[j].id))
		CombatSim.run(state)
		var l := DamageLedger.build(state)
		print("\n=== room %d  %s  (%d ticks, %.0fs)" % [i + 1, String(room.content_id), state.tick, state.tick / 15.0])
		if not revived.is_empty():
			print("  CAMP: revived %s" % ", ".join(revived))
		var rows := []
		for aid in l.by_ability.get(CG.Team.PLAYER, {}):
			var r = l.by_ability[CG.Team.PLAYER][aid]
			rows.append([int(r.total), String(aid), int(r.casts)])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		var top := []
		for k in mini(3, rows.size()):
			top.append("%s %d/%d hits" % [rows[k][1], rows[k][0], rows[k][2]])
		print("  damage: %s" % "; ".join(top))
		var m = l.mitigation.get(CG.Team.PLAYER, {}).get("totals", null)
		if m != null and m.before > 0:
			print("  armour stopped %d%%" % int(round(100.0 * (m.before - m.after) / m.before)))
		var line: Array[String] = []
		var dead: Array[String] = []
		for j in party.size():
			var u := state.unit(j)
			if not u.alive:
				dead.append(String(party[j].id))
			line.append("%s %d/%d" % [String(party[j].id).substr(0, 4), u.hp, u.hp_max])
			run.record_result(party[j].id, u.hp, u.resource, u.alive)
		var had := run.loot.size()
		if state.outcome == CombatState.Outcome.PLAYER_WIN:
			FloorRun.award_room_loot(run, room, party, 36)
		if run.loot.size() > had:
			print("  LOOT: %s" % String(run.loot[run.loot.size() - 1].id))
		print("  end: %s" % "  ".join(line))
		if not dead.is_empty():
			print("  DIED: %s" % ", ".join(dead))
	quit(0)
