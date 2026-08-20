extends SceneTree

## Issue 218. How often does a fight outlive the whole party, and for how long?
##
##   godot --headless --path . --script res://Tools/PawnlessProbe.gd
##
## Not part of the gate. It answers three questions the win table cannot,
## because a win table has one row per party and this is a property of the
## *tail* of a fight:
##
##   1. How many fights end with every pawn dead and a summon still standing?
##   2. In those, how many ticks pass between the last pawn dying and the
##      fight ending -- i.e. how long the player watches a fight containing
##      nothing they authored?
##   3. What outcome do those tails reach: a win, a loss, or the tick cap?
##
## Question 2 is the one worth the tool. A pawnless win reported as "1 fight in
## 800" sounds like a rounding error; a pawnless *tail* is a different and much
## more common event, and it is the one a player actually sees.


const SEEDS := 40

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()

	var total := 0
	var tails := 0
	var tail_wins := 0
	var tail_losses := 0
	var tail_draws := 0
	var tail_lengths: Array[int] = []

	for encounter_id in encounter_ids:
		var encounter := Registry.get_encounter(encounter_id)
		for party_ids in _parties(class_ids):
			var rows := 0
			var row_wins := 0
			var row_len_sum := 0
			for s in SEEDS:
				var party: Array[PawnData] = []
				for cid in party_ids:
					party.append(PawnFactory.make_starter_pawn(
						cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
				var state := CombatSim.build(party, encounter, s)
				var last_pawn_death := _run_and_watch(state)
				total += 1
				if last_pawn_death < 0:
					continue
				var length := state.tick - last_pawn_death
				# An ordinary loss wipes the party and ends on the same tick.
				# That is length 0 and it is not a tail; excluding it is what
				# keeps this from reporting every defeat as a finding.
				if length <= 0:
					continue
				# A pawnless tail: every pawn dead, and the fight kept running.
				rows += 1
				tails += 1
				tail_lengths.append(length)
				row_len_sum += length
				match state.outcome:
					CombatState.Outcome.PLAYER_WIN:
						tail_wins += 1
						row_wins += 1
					CombatState.Outcome.ENEMY_WIN:
						tail_losses += 1
					_:
						tail_draws += 1
			if rows > 0:
				print("%s / %s: %d/%d fights have a pawnless tail, %d won, mean tail %.1f ticks (%.1fs)" % [
					encounter_id, "+".join(PackedStringArray(party_ids)),
					rows, SEEDS, row_wins,
					float(row_len_sum) / float(rows),
					float(row_len_sum) / float(rows) / float(CG.TICKS_PER_SECOND)])

	print("")
	print("fights: ", total)
	print("pawnless tails: %d (%.2f%%)" % [tails, 100.0 * float(tails) / float(maxi(total, 1))])
	print("  reaching PLAYER_WIN: ", tail_wins)
	print("  reaching ENEMY_WIN:  ", tail_losses)
	print("  reaching the cap:    ", tail_draws)
	if not tail_lengths.is_empty():
		tail_lengths.sort()
		var median := tail_lengths[tail_lengths.size() / 2]
		print("  tail length ticks: min %d median %d max %d" % [
			tail_lengths[0], median, tail_lengths[tail_lengths.size() - 1]])
		print("  median tail seconds: %.1f" % (float(median) / float(CG.TICKS_PER_SECOND)))
	quit(0)

## Steps the fight by hand so the tick the last pawn dies can be seen. Returns
## that tick, or -1 if a pawn was alive when the fight ended (the ordinary case).
func _run_and_watch(state: CombatState) -> int:
	var last_pawn_death := -1
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		if last_pawn_death < 0 and _living_pawns(state) == 0:
			last_pawn_death = state.tick
	if _living_pawns(state) > 0:
		return -1
	return last_pawn_death

static func _living_pawns(state: CombatState) -> int:
	var n := 0
	for u in state.units:
		if u.alive and u.team == CG.Team.PLAYER and u.pawn != null:
			n += 1
	return n

func _parties(class_ids: Array) -> Array:
	var out := []
	if class_ids.size() > 4:
		for skip in class_ids.size():
			var party := []
			for i in class_ids.size():
				if i != skip:
					party.append(class_ids[i])
			out.append(party)
	elif class_ids.size() >= 1:
		out.append(class_ids.slice(0, mini(4, class_ids.size())))
	return out
