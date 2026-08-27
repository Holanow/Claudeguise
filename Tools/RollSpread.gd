extends SceneTree

## Issue 131: what randomising a pawn's attributes does to the outcome table.
## Reported, never compensated for -- the spread is a feature the player asked
## for and no number here may be used to tune it.
##
## Both arms run the same rooms, parties and fight seeds. The rolled arm rolls
## its pawns from that same seed, which is what the party-select screen does.

const SEEDS := 60

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	var parties := _parties(class_ids)
	var totals := {&"fixed": _Acc.new(), &"rolled": _Acc.new()}

	for encounter_id in Registry.pickable_encounter_ids():
		var encounter := Registry.get_encounter(encounter_id)
		print("")
		print("======== ", encounter_id, " ========")
		for arm in [&"fixed", &"rolled"]:
			var acc := _Acc.new()
			for party_ids in parties:
				for s in SEEDS:
					var party: Array[PawnData] = []
					for cid in party_ids:
						var pid := StringName("%s_%d" % [cid, party.size()])
						party.append(
							PawnFactory.make_rolled_pawn(cid, pid, String(cid), s) if arm == &"rolled"
							else PawnFactory.make_starter_pawn(cid, pid, String(cid))
						)
					var state := CombatSim.build(party, encounter, s)
					var outcome := CombatSim.run(state)
					acc.add(outcome, state)
					totals[arm].add(outcome, state)
			print("  %-8s %s" % [arm, acc.line()])

	print("")
	print("======== ALL PICKABLE ROOMS, ALL BUILDABLE PARTIES ========")
	for arm in [&"fixed", &"rolled"]:
		print("  %-8s %s" % [arm, totals[arm].line()])

	print("")
	print("======== how far one seed moves a pawn ========")
	for cid in class_ids:
		var line := PackedStringArray()
		for s in 6:
			var pawn := PawnFactory.make_rolled_pawn(cid, &"p", "p", s)
			var parts := PackedStringArray()
			for a in PawnFactory.ROLLED_ATTRIBUTES:
				parts.append("%s%+d" % [CG.attribute_name(a), int(pawn.attribute_bonus.get(a, 0))])
			line.append("[" + " ".join(parts) + "]")
		print("  %-14s %s" % [String(cid), " ".join(line)])
	## Issue 485 requires this in #484's own form: mean against baseline, per
	## class and per attribute. Two different quantities are printed, because
	## conflating them is how a floor artifact would hide inside the levelling.
	print("")
	print("======== mean against BASELINE over 500 seeds (this is the levelling) ========")
	for cid in class_ids:
		var cls := ClassLibrary.get_class_def(cid)
		var sums := _means(cid)
		var parts := PackedStringArray()
		for a in PawnFactory.ROLLED_ATTRIBUTES:
			parts.append("%s %d->%.2f" % [CG.attribute_name(a), cls.attribute(a), sums[a]])
		print("  %-14s total %2d->%2d  %s" % [
			String(cid), PawnFactory.class_total(cls), PawnFactory.POOL_SIZE, " ".join(parts)])

	print("")
	print("======== mean against the DISTRIBUTION'S OWN EXPECTATION (this is the floor check) ========")
	for cid in class_ids:
		var cls := ClassLibrary.get_class_def(cid)
		var sums := _means(cid)
		var free := float(PawnFactory.POOL_SIZE - PawnFactory.floor_cost(cls))
		var weight_total := float(PawnFactory.class_total(cls))
		var parts := PackedStringArray()
		for a in PawnFactory.ROLLED_ATTRIBUTES:
			var expected: float = float(PawnFactory.attribute_floor(cls, a)) 				+ free * float(cls.attribute(a)) / maxf(1.0, weight_total)
			parts.append("%s %+.2f" % [CG.attribute_name(a), sums[a] - expected])
		print("  %-14s %s" % [String(cid), " ".join(parts)])

	## A floor rarely reached is fine; one reached constantly is issue 484
	## returning under another name.
	print("")
	print("======== how often an attribute sits exactly on its floor, of 500 ========")
	for cid in class_ids:
		var cls := ClassLibrary.get_class_def(cid)
		var at_floor := {}
		for s in 500:
			var pawn := PawnFactory.make_rolled_pawn(cid, &"p", "p", s)
			for a in PawnFactory.ROLLED_ATTRIBUTES:
				if pawn.attribute(a) == PawnFactory.attribute_floor(cls, a):
					at_floor[a] = int(at_floor.get(a, 0)) + 1
		var parts := PackedStringArray()
		for a in PawnFactory.ROLLED_ATTRIBUTES:
			parts.append("%s %d/%d(floor %d)" % [
				CG.attribute_name(a), int(at_floor.get(a, 0)), 500, PawnFactory.attribute_floor(cls, a)])
		print("  %-14s free %2d  %s" % [
			String(cid), PawnFactory.POOL_SIZE - PawnFactory.floor_cost(cls), " ".join(parts)])
	quit(0)

func _parties(class_ids: Array) -> Array:
	if class_ids.size() <= 4:
		return [class_ids.duplicate()]
	var out := []
	for skip in class_ids.size():
		var party := []
		for i in class_ids.size():
			if i != skip:
				party.append(class_ids[i])
		out.append(party)
	return out

class _Acc extends RefCounted:
	var wins := 0
	var total := 0
	var ticks: Array[int] = []
	var hp: Array[int] = []

	func add(outcome: int, state: CombatState) -> void:
		total += 1
		if outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
		ticks.append(state.tick)
		hp.append(_team_hp_percent(state))

	func line() -> String:
		return "%4d/%4d (%5.1f%%)   median party hp %2d%%   median ticks %4d" % [
			wins, total, 100.0 * float(wins) / float(maxi(1, total)), _median(hp), _median(ticks),
		]

	static func _team_hp_percent(state: CombatState) -> int:
		var h := 0
		var h_max := 0
		for u in state.units:
			if u.team != CG.Team.PLAYER or u.pawn == null:
				continue
			h += maxi(0, u.hp)
			h_max += u.hp_max
		return 0 if h_max <= 0 else int(round(100.0 * float(h) / float(h_max)))

	static func _median(a: Array[int]) -> int:
		if a.is_empty():
			return 0
		var c := a.duplicate()
		c.sort()
		return c[c.size() / 2]

## Mean value of each rolled attribute over 500 seeds.
func _means(class_id: StringName) -> Dictionary:
	var sums := {}
	for s in 500:
		var pawn := PawnFactory.make_rolled_pawn(class_id, &"p", "p", s)
		for a in PawnFactory.ROLLED_ATTRIBUTES:
			sums[a] = float(sums.get(a, 0.0)) + float(pawn.attribute(a))
	for a in PawnFactory.ROLLED_ATTRIBUTES:
		sums[a] = float(sums[a]) / 500.0
	return sums
