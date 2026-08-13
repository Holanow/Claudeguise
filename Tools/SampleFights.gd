extends SceneTree

## Runs the real encounter with real content across many seeds and prints what
## happened.
##
##   godot --headless --path . --script res://Tools/SampleFights.gd
##
## MANAGER-OWNED. Not part of the game and not part of the gate.
##
## This exists because every other thing I look at is a report *about* the work,
## and most of them are written by whoever is being reviewed. A test suite says a
## fight resolves. It does not say whether the fights are all the same length,
## whether one party composition wins every time, or whether the encounter is a
## coin flip. Those are properties of the assembled whole, and review inspects
## parts.
##
## It deliberately measures rather than renders: how long, how close, who died.
## If a fight is decided in two seconds or takes the full two minutes, nobody
## needs to watch it to know something is wrong.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

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
	#
	# This used to sample `encounter_ids[0]`, which was correct while exactly one
	# encounter existed and became silently wrong the moment a second appeared:
	# the list is sorted alphabetically, so `floor1_ghoul_den` displaced
	# `floor1_room1` and the tool went on printing confident numbers about a room
	# nobody was tuning. teal caught it after two rounds of retuning produced
	# byte-identical output and they went looking for why instead of assuming
	# their edit had not mattered.
	#
	# The fix is not an argument for choosing the encounter. It is measuring all
	# of them and putting the name above each table, so there is no index to be
	# wrong about and no way to read a number without seeing what it is a number
	# for.
	for encounter_id in encounter_ids:
		print("")
		print("========================================================")
		print("ENCOUNTER: ", encounter_id)
		print("========================================================")
		var encounter := Registry.get_encounter(encounter_id)
		# Every party of four from the five classes, so "does composition matter"
		# is answered across compositions rather than from one that happened to
		# be tried. One party would only say whether that party wins.
		for party_ids in _parties(class_ids):
			_sample(party_ids, encounter)

	quit(0)

func _parties(class_ids: Array) -> Array:
	var out := []
	# The first four, the last four, and four of a kind for each class.
	if class_ids.size() >= 4:
		out.append(class_ids.slice(0, 4))
		out.append(class_ids.slice(class_ids.size() - 4, class_ids.size()))
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
		survivors.append(state.living(CG.Team.PLAYER).size())
		margins.append(_losing_side_hp_percent(state, outcome))
		# Cost is recorded for won fights only. See the comment on the cost line
		# below for why the all-fights version of this was actively misleading.
		if outcome == CombatState.Outcome.PLAYER_WIN:
			party_hp.append(_team_hp_percent(state, CG.Team.PLAYER))
			win_survivors.append(state.living(CG.Team.PLAYER).size())

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
	#
	#   "If a team wins 75% of the time but they do it with 2 members down and
	#    the other 2 almost dead I would call that fine pretty much."
	#
	# So a high win rate is not the failure. A high win rate that costs nothing
	# is. Win count alone cannot tell those apart and it is what we had been
	# steering by all evening.
	#
	# Measured over WON fights only, which the first version of this did not do.
	# A median across all twenty is dominated by the losses, where the party
	# finishes on 0% by definition — so `priest x4`, which won one fight in
	# twenty, was printing "COSTLY WIN: this is the shape we want" beside a row
	# that is simply a party losing. The label describes what winning costs, so
	# it has to be computed from the fights that were won.
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
##
## This is the number issue 7 is really about. A win/loss record says which side
## won; it says nothing about whether it was close. 0% means the loser was wiped
## out — which is what every fight in this project has been so far. Anything
## above about 15% is a fight that could have gone the other way.
##
## Measured on the side that lost, so it reads the same whoever wins. A draw is
## measured on the party, since a draw is a failure to finish rather than a win.
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

## The verdict line. A fight is fine when winning costs the winner something,
## whatever the win rate is; it is a problem when a party wins without being
## touched, and a different problem when the party is simply losing.
func _cost_note(party_hp: int, survivors: int) -> String:
	if party_hp >= 85 and survivors >= 4:
		return "   <- UNTOUCHED: winning costs nothing"
	if party_hp <= 40 or survivors <= 2:
		return "   <- COSTLY WIN: this is the shape we want"
	return "   <- some cost"
