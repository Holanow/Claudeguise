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

	var encounter := Registry.get_encounter(encounter_ids[0])

	# Every party of four from the five classes, so "does composition matter"
	# is answered across compositions rather than from one that happened to be
	# tried. One party would only say whether that party wins.
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

	print("")
	print("party: ", _short(party_ids))
	print("  win %d / lose %d / draw %d  of %d" % [wins, losses, draws, SEEDS])
	print("  ticks   min %d  median %d  max %d   (%.1fs .. %.1fs)" % [
		_min(ticks), _median(ticks), _max(ticks),
		float(_min(ticks)) / float(CG.TICKS_PER_SECOND),
		float(_max(ticks)) / float(CG.TICKS_PER_SECOND),
	])
	print("  party survivors: min %d  median %d  max %d" % [
		_min(survivors), _median(survivors), _max(survivors)
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
