extends SceneTree

## Runs the real encounter with real content across many seeds and prints what
## happened.


const SEEDS := 20

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()
	print("classes: ", class_ids)
	print("encounters: ", encounter_ids)
	if class_ids.is_empty() or encounter_ids.is_empty():
		printerr("no content registered; nothing to sample")
		quit(1)
		return

	# EVERY encounter, named in the output, rather than one picked by index.
	for encounter_id in encounter_ids:
		print("")
		print("========================================================")
		print("ENCOUNTER: ", encounter_id)
		print("========================================================")
		var encounter := Registry.get_encounter(encounter_id)
		# Real parties first, and they are the only ones any balance decision
		# should be read from. See _parties for why that sentence had to be
		# written down.
		print("")
		print("-- PARTIES A PLAYER CAN BUILD ---------------------------")
		for party_ids in _parties(class_ids):
			_sample(party_ids, encounter)
		print("")
		print("-- NOT BUILDABLE: one class four times, per-class diagnostic only")
		print("-- PartySelect allows one card per class. Do not balance on these.")
		for party_ids in _impossible_parties(class_ids):
			_sample(party_ids, encounter)

	quit(0)

## Every party a player can actually assemble, and then the ones they cannot,
## labelled as such.
func _parties(class_ids: Array) -> Array:
	var out := []
	if class_ids.size() > 4:
		# Leave-one-out: the real parties, in the order a player would see the
		# cards, with the excluded class named in the output.
		for skip in class_ids.size():
			var party := []
			for i in class_ids.size():
				if i != skip:
					party.append(class_ids[i])
			out.append(party)
	elif class_ids.size() >= 1:
		out.append(class_ids.slice(0, mini(4, class_ids.size())))
	return out

## Not buildable in `PartySelect`. Kept as a per-class diagnostic only.
func _impossible_parties(class_ids: Array) -> Array:
	var out := []
	for id in class_ids:
		out.append([id, id, id, id])
	return out

func _sample(party_ids: Array, encounter) -> void:
	var wins := 0
	var losses := 0
	var draws := 0
	var ticks: Array[int] = []
	var survivors: Array[int] = []
	var margins: Array[int] = []
	var party_hp: Array[int] = []
	var win_survivors: Array[int] = []

	for s in SEEDS:
		var party: Array[PawnData] = []
		for cid in party_ids:
			party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
		var state := CombatSim.build(party, encounter, s)
		var outcome := CombatSim.run(state)
		match outcome:
			CombatState.Outcome.PLAYER_WIN: wins += 1
			CombatState.Outcome.ENEMY_WIN: losses += 1
			_: draws += 1
		ticks.append(state.tick)
		survivors.append(_living_pawns(state))
		margins.append(_losing_side_hp_percent(state, outcome))
		# Cost is recorded for won fights only. See the comment on the cost line
		# below for why the all-fights version of this was actively misleading.
		if outcome == CombatState.Outcome.PLAYER_WIN:
			party_hp.append(_team_hp_percent(state, CG.Team.PLAYER))
			win_survivors.append(_living_pawns(state))

	print("")
	print("party: ", _short(party_ids))
	print("  win %d / lose %d / draw %d  of %d%s" % [
		wins, losses, draws, SEEDS,
		"   <- COIN FLIP" if wins >= 6 and wins <= 14 else "",
	])
	print("  ticks   min %d  median %d  max %d   (%.1fs .. %.1fs)  spread %d%%" % [
		_min(ticks), _median(ticks), _max(ticks),
		float(_min(ticks)) / float(CG.TICKS_PER_SECOND),
		float(_max(ticks)) / float(CG.TICKS_PER_SECOND),
		_spread_percent(ticks),
	])
	# A histogram, not a median. "median 4" and "median 4 every single time" are
	# very different games and the median cannot tell them apart, which is the
	# whole question issue 7 is about.
	print("  survivors  %s" % _histogram(survivors, 4))
	# A draw is never "close": it is a fight that failed to finish, and the
	# losing side has hp left because nobody could reach anybody. The first
	# version of this flagged the 120-second stalemate as CLOSE, which would
	# have pointed teal at exactly the wrong conclusion.
	var close_note := ""
	if draws == 0 and _median(margins) >= 15:
		close_note = "   <- CLOSE"
	elif draws > 0:
		close_note = "   (draws excluded: a stalemate is not a close fight)"
	print("  closeness  losing side finished on median %d%% hp%s" % [
		_median(margins), close_note,
	])
	# The number the user asked for, and it changes what "balanced" means.
	if wins == 0:
		print("  cost       no wins to measure")
	else:
		print("  cost       party finished its %d win%s on median %d%% of its own hp%s" % [
			wins, "" if wins == 1 else "s",
			_median(party_hp), _cost_note(_median(party_hp), _median(win_survivors)),
		])

func _short(ids: Array) -> String:
	var parts := PackedStringArray()
	for i in ids:
		parts.append(String(i))
	return ", ".join(parts)

func _min(a: Array[int]) -> int:
	var v := a[0]
	for x in a:
		v = mini(v, x)
	return v

func _max(a: Array[int]) -> int:
	var v := a[0]
	for x in a:
		v = maxi(v, x)
	return v

func _median(a: Array[int]) -> int:
	var c := a.duplicate()
	c.sort()
	return c[c.size() / 2]


## How much hp the losing side had left, as a percentage of its starting total.
func _losing_side_hp_percent(state, outcome: int) -> int:
	var team := CG.Team.PLAYER
	if outcome == CombatState.Outcome.ENEMY_WIN:
		team = CG.Team.PLAYER
	elif outcome == CombatState.Outcome.PLAYER_WIN:
		team = CG.Team.ENEMY
	var hp := 0
	var hp_max := 0
	for u in state.units:
		if u.team != team:
			continue
		hp += maxi(0, u.hp)
		hp_max += u.hp_max
	if hp_max <= 0:
		return 0
	return int(round(100.0 * float(hp) / float(hp_max)))

## max - min as a percentage of the median. Issue 7 criterion 2 asks for at
## least 15%: below that the seed is not really changing the fight.
func _spread_percent(a: Array[int]) -> int:
	var m := _median(a)
	if m <= 0:
		return 0
	return int(round(100.0 * float(_max(a) - _min(a)) / float(m)))

func _histogram(a: Array[int], upper: int) -> String:
	var counts := {}
	for x in a:
		counts[x] = int(counts.get(x, 0)) + 1
	var parts := PackedStringArray()
	for i in range(upper + 1):
		parts.append("%d:%s" % [i, str(counts.get(i, 0)).rpad(3)])
	return " ".join(parts)


## What a side has left, as a percentage of that side's starting hp. Dead units
## count as zero rather than being dropped, so a party of four with two dead and
## two at half reads as 25% — which is the shape the user described as fine.
func _team_hp_percent(state, team: int) -> int:
	var hp := 0
	var hp_max := 0
	for u in state.units:
		if u.team != team:
			continue
		hp += maxi(0, u.hp)
		hp_max += u.hp_max
	if hp_max <= 0:
		return 0
	return int(round(100.0 * float(hp) / float(hp_max)))

## The verdict line, and its polarity is reversed from the version rook
## wrote it with.
## Living pawns, not living player-team units. A Siege Engine is on the player
## team, so counting units puts five or six in a party of four and every
## survivor bucket lands out of range.
static func _living_pawns(state: CombatState) -> int:
	var n := 0
	for u in state.living(CG.Team.PLAYER):
		if u.pawn != null:
			n += 1
	return n

func _cost_note(party_hp: int, survivors: int) -> String:
	if party_hp >= 55 and survivors >= 4:
		return "   <- COMFORTABLE WIN: matches the player's own single-fight target"
	if party_hp <= 40 or survivors <= 2:
		return "   <- CLOSE WIN: fine as an occasional room, a problem if every fight looks like this"
	return "   <- some cost"
