extends SceneTree

## Issue 356: how often the player loses, how often a party pawn dies, and
## whether the party choice changes either.


const SEEDS := 40

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	var encounter_ids := RoomLibrary.pickable_ids()
	print("classes: ", class_ids)
	print("pickable encounters: ", encounter_ids)

	var rows := []
	for encounter_id in encounter_ids:
		var encounter := RoomLibrary.get_room(encounter_id)
		print("")
		print("ENCOUNTER: %s  (%s)" % [encounter_id, encounter.display_name])
		print("  %-42s %6s %6s %6s   %s" % ["party (class left out)", "loss", "draw", "anydeath", "pawns dead 0/1/2/3/4"])
		var room_losses := 0
		var room_deaths := 0
		var room_fights := 0
		var per_party_loss := []
		for skip in class_ids.size():
			var party_ids := []
			for i in class_ids.size():
				if i != skip:
					party_ids.append(class_ids[i])
			var r := _sample(party_ids, encounter)
			r["encounter"] = encounter_id
			r["left_out"] = class_ids[skip]
			rows.append(r)
			room_losses += int(r["losses"])
			room_deaths += int(r["fights_with_a_death"])
			room_fights += SEEDS
			per_party_loss.append(int(r["losses"]))
			print("  %-42s %5d%% %5d%% %5d%%   %s   dead: %s" % [
				"-" + String(class_ids[skip]),
				int(round(100.0 * float(r["losses"]) / float(SEEDS))),
				int(round(100.0 * float(r["draws"]) / float(SEEDS))),
				int(round(100.0 * float(r["fights_with_a_death"]) / float(SEEDS))),
				_histogram(r["dead_counts"], 4),
				_who(r["deaths_by_class"]),
			])
		print("  ROOM: loss %d%%, a pawn died in %d%% of fights, party-choice loss spread %d..%d of %d" % [
			int(round(100.0 * float(room_losses) / float(room_fights))),
			int(round(100.0 * float(room_deaths) / float(room_fights))),
			_min(per_party_loss), _max(per_party_loss), SEEDS,
		])

	print("")
	print("======== EVERY PARTY x EVERY PICKABLE ROOM ========")
	var total_fights := rows.size() * SEEDS
	var total_losses := 0
	var total_draws := 0
	var total_deaths := 0
	var total_wipes := 0
	var clean := 0
	for r in rows:
		total_losses += int(r["losses"])
		total_draws += int(r["draws"])
		total_deaths += int(r["fights_with_a_death"])
		total_wipes += int(r["wipes"])
		clean += int(r["dead_counts"].get(0, 0))
	print("fights            %d  (%d parties x %d rooms x %d seeds)" % [total_fights, 5, rows.size() / 5, SEEDS])
	print("player loses      %d  (%.1f%%)" % [total_losses, 100.0 * float(total_losses) / float(total_fights)])
	print("draws             %d  (%.1f%%)" % [total_draws, 100.0 * float(total_draws) / float(total_fights)])
	print("no pawn dies      %d  (%.1f%%)" % [clean, 100.0 * float(clean) / float(total_fights)])
	print("some pawn dies    %d  (%.1f%%)" % [total_deaths, 100.0 * float(total_deaths) / float(total_fights)])
	print("whole party dies  %d  (%.1f%%)" % [total_wipes, 100.0 * float(total_wipes) / float(total_fights)])
	quit(0)

func _sample(party_ids: Array, encounter) -> Dictionary:
	var losses := 0
	var draws := 0
	var wipes := 0
	var fights_with_a_death := 0
	var dead_counts := {}
	var deaths_by_class := {}

	for s in SEEDS:
		var party: Array[PawnData] = []
		for cid in party_ids:
			party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
		var state := CombatSim.build(party, encounter, s)
		var outcome := CombatSim.run(state)
		if outcome == CombatState.Outcome.ENEMY_WIN:
			losses += 1
		elif outcome != CombatState.Outcome.PLAYER_WIN:
			draws += 1
		var dead := 0
		for u in state.units:
			# Party pawns only. A summoned siege engine is not a party member,
			# and counting one masks a death.
			if u.team != CG.Team.PLAYER or u.pawn == null:
				continue
			if not u.alive:
				dead += 1
				var cid: StringName = u.pawn.pawn_class.id if u.pawn.pawn_class != null else &"?"
				deaths_by_class[cid] = int(deaths_by_class.get(cid, 0)) + 1
		dead_counts[dead] = int(dead_counts.get(dead, 0)) + 1
		if dead > 0:
			fights_with_a_death += 1
		if dead >= party_ids.size():
			wipes += 1

	return {
		"losses": losses,
		"draws": draws,
		"wipes": wipes,
		"fights_with_a_death": fights_with_a_death,
		"dead_counts": dead_counts,
		"deaths_by_class": deaths_by_class,
	}

func _histogram(counts: Dictionary, upper: int) -> String:
	var parts := PackedStringArray()
	for i in range(upper + 1):
		parts.append("%d:%s" % [i, str(counts.get(i, 0)).rpad(3)])
	return " ".join(parts)

func _who(deaths_by_class: Dictionary) -> String:
	var keys := deaths_by_class.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s %d" % [String(k), int(deaths_by_class[k])])
	return ", ".join(parts) if parts.size() > 0 else "none"

func _min(a: Array) -> int:
	var v := int(a[0])
	for x in a:
		v = mini(v, int(x))
	return v

func _max(a: Array) -> int:
	var v := int(a[0])
	for x in a:
		v = maxi(v, int(x))
	return v
