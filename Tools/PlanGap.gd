extends SceneTree

## What authoring plan rows is worth: the same parties and seeds run unedited,
## with one library row each, and with the whole library.


const SEEDS := 20

## Arms, in report order. `only_*` arms plan one class and leave the other three
## unedited, which is how much of the gap belongs to that class.
const ARM_UNEDITED := &"unedited"
const ARM_FIRST := &"first_row"
const ARM_LIBRARY := &"library"

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	var encounter_ids := Registry.pickable_encounter_ids()
	print("classes: ", class_ids)
	print("pickable encounters: ", encounter_ids)

	_print_budgets(class_ids)

	var arms: Array[StringName] = [ARM_UNEDITED, ARM_FIRST, ARM_LIBRARY]
	for cid in class_ids:
		arms.append(StringName("only_%s" % cid))
	for cid in class_ids:
		arms.append(StringName("firstonly_%s" % cid))

	var parties := _parties(class_ids)
	var totals := {}
	var by_party := {}
	for arm in arms:
		totals[arm] = _Acc.new()
		for p in parties:
			by_party[[arm, _short(p)]] = _Acc.new()

	for encounter_id in encounter_ids:
		var encounter := Registry.get_encounter(encounter_id)
		print("")
		print("======== ", encounter_id, " ========")
		print("  %-22s %-14s %-22s %s" % ["arm", "player wins", "party hp at end", "ticks"])
		for arm in arms:
			var acc := _Acc.new()
			for party_ids in parties:
				var accs: Array[_Acc] = [acc, totals[arm], by_party[[arm, _short(party_ids)]]]
				_sample(party_ids, encounter, arm, accs)
			print("  %-22s %s" % [arm, acc.line()])

	print("")
	print("======== ALL PICKABLE ROOMS, ALL BUILDABLE PARTIES ========")
	print("  %-22s %-14s %-22s %s" % ["arm", "player wins", "party hp at end", "ticks"])
	for arm in arms:
		print("  %-22s %s" % [arm, totals[arm].line()])

	print("")
	print("======== PER PARTY, all six rooms ========")
	for party_ids in parties:
		print("  party %s" % _short(party_ids))
		for arm in [ARM_UNEDITED, ARM_FIRST, ARM_LIBRARY]:
			print("    %-12s %s" % [arm, by_party[[arm, _short(party_ids)]].line()])

	quit(0)

## How many library rows a pawn can actually run. `PlanInterpreter` stops at the
## WIS budget, so the whole library is not the same thing as the whole library
## firing.
func _print_budgets(class_ids: Array) -> void:
	print("")
	print("======== how much of a library a pawn can run ========")
	for cid in class_ids:
		var pawn := PawnFactory.make_preset_pawn(cid, StringName("b_%s" % cid), String(cid))
		print("  %-14s rows %d  blocks %d  budget %d  ACTIVE ROWS %d" % [
			String(cid), pawn.plans.size(), PresetPlans.total_blocks(cid),
			Balance.plan_block_budget(pawn), PlanInterpreter.active_plan_count(pawn),
		])

## Leave-one-out, which is every party a `PartySelect` of five classes can build
## and covers every class. At four or fewer there is only one party and it is the
## whole roster; issue 350 is why neither branch takes a prefix of it.
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

## `only_*` gives one class its whole library; `firstonly_*` gives one class its
## top row alone. Every other pawn in both stays unedited.
func _make_pawn(class_id: StringName, pawn_id: StringName, arm: StringName) -> PawnData:
	var whole := arm == ARM_LIBRARY or String(arm) == "only_%s" % class_id
	var one_row := arm == ARM_FIRST or String(arm) == "firstonly_%s" % class_id
	if not whole and not one_row:
		return PawnFactory.make_starter_pawn(class_id, pawn_id, String(class_id))
	var pawn := PawnFactory.make_preset_pawn(class_id, pawn_id, String(class_id))
	if one_row:
		var top: Array[Plan] = []
		if not pawn.plans.is_empty():
			top.append(pawn.plans[0])
		pawn.plans = top
	return pawn

func _sample(party_ids: Array, encounter, arm: StringName, accs: Array[_Acc]) -> void:
	for s in SEEDS:
		var party: Array[PawnData] = []
		for cid in party_ids:
			party.append(_make_pawn(cid, StringName("%s_%d" % [cid, party.size()]), arm))
		var state := CombatSim.build(party, encounter, s)
		var outcome := CombatSim.run(state)
		for acc in accs:
			acc.add(outcome, state)

func _short(ids: Array) -> String:
	var parts := PackedStringArray()
	for i in ids:
		parts.append(String(i))
	return ", ".join(parts)

## One arm's fights, folded into the four numbers the report prints.
class _Acc extends RefCounted:
	var wins := 0
	var losses := 0
	var draws := 0
	var ticks: Array[int] = []
	var hp: Array[int] = []
	var win_hp: Array[int] = []
	var survivors: Array[int] = []
	## Order-sensitive fold over every fight's outcome, tick and end hp. Two arms
	## with the same digest ran the same fights, so a row that changes nothing is
	## told apart from a row whose effect the medians happen to hide.
	var digest := 0

	func add(outcome: int, state: CombatState) -> void:
		match outcome:
			CombatState.Outcome.PLAYER_WIN: wins += 1
			CombatState.Outcome.ENEMY_WIN: losses += 1
			_: draws += 1
		ticks.append(state.tick)
		var pct := _team_hp_percent(state)
		hp.append(pct)
		survivors.append(_living_pawns(state))
		if outcome == CombatState.Outcome.PLAYER_WIN:
			win_hp.append(pct)
		digest = (digest * 131 + outcome * 1000003 + state.tick * 101 + pct) % 1000000007

	func total() -> int:
		return wins + losses + draws

	func line() -> String:
		return "%3d/%3d (%5.1f%%)  all %3d%%  wins %3d%%  alive %.2f  med %4d (%4.1fs)  loss %d draw %d" % [
			wins, total(), 100.0 * float(wins) / float(maxi(1, total())),
			_median(hp), _median(win_hp), _mean(survivors),
			_median(ticks), float(_median(ticks)) / float(CG.TICKS_PER_SECOND),
			losses, draws,
		] + ("  digest %d" % digest)

	## Pawns only. A summoned Siege Engine is on the player team, so counting
	## units would put the planned arm's own summon into its denominator.
	static func _team_hp_percent(state: CombatState) -> int:
		var h := 0
		var h_max := 0
		for u in state.units:
			if u.team != CG.Team.PLAYER or u.pawn == null:
				continue
			h += maxi(0, u.hp)
			h_max += u.hp_max
		if h_max <= 0:
			return 0
		return int(round(100.0 * float(h) / float(h_max)))

	static func _living_pawns(state: CombatState) -> int:
		var n := 0
		for u in state.living(CG.Team.PLAYER):
			if u.pawn != null:
				n += 1
		return n

	static func _median(a: Array[int]) -> int:
		if a.is_empty():
			return 0
		var c := a.duplicate()
		c.sort()
		return c[c.size() / 2]

	static func _mean(a: Array[int]) -> float:
		if a.is_empty():
			return 0.0
		var t := 0
		for x in a:
			t += x
		return float(t) / float(a.size())
