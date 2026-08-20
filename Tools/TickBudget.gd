extends SceneTree

## Does any fight run out of tick budget?
##
##   godot --headless --path . --script res://Tools/TickBudget.gd
##
## MANAGER-OWNED. Not part of the game and not part of the gate.
##
## Written to check a second-order effect of halving the fight speed that
## nobody measured, including the session that made the change.
##
## `CG.MAX_TICKS` is `TICKS_PER_SECOND * 120` -- "two minutes of wall clock".
## Halving the tick rate therefore halved the budget in *ticks*, 3600 -> 1800,
## while every content tick value (wind-ups, cooldowns, travel) stayed exactly
## where it was. The wall-clock cap is unchanged; the simulation budget is
## half what it was.
##
## That matters because a fight which exceeds it does not report as a timeout.
## `CombatSim` resolves it to DRAW, the same value a mutual wipe produces, so
## every run tool in this repo counts it as "not a win" and nothing anywhere
## says the fight was cut off. A budget cut in half is exactly the change that
## would start producing them.
##
## Reports the worst case rather than an average: the longest fight seen, and
## any fight that actually hit the ceiling.


const SEEDS := 20

## The five parties the game can actually build: one card per class, four
## slots, five classes, so every real party is a leave-one-out. Mono-class
## rosters are not reachable and tuning against them wasted three issues.
const CLASSES := ["warrior", "priest", "abomination", "geysermancer", "siege_master"]

func _init() -> void:
	print("MAX_TICKS = %d  (TICKS_PER_SECOND %d x 120s)" % [CG.MAX_TICKS, CG.TICKS_PER_SECOND])
	print("")

	var worst := 0
	var worst_label := ""
	var capped := 0
	var fights := 0

	for left_out in CLASSES:
		var ids: Array = []
		for c in CLASSES:
			if c != left_out:
				ids.append(c)

		for enc_id in Registry.all_encounter_ids():
			var longest := 0
			var hit := 0
			for s in range(SEEDS):
				var state := _run(ids, enc_id, s)
				fights += 1
				if state.tick > longest:
					longest = state.tick
				# A fight is cut off only if it burned the whole budget while
				# both sides still had someone standing. A mutual wipe also
				# reports DRAW and is a real outcome, not a truncation.
				if state.tick >= CG.MAX_TICKS:
					hit += 1
					capped += 1
			if longest > worst:
				worst = longest
				worst_label = "no_%s @ %s" % [left_out, enc_id]
			if hit > 0:
				print("  CUT OFF  no_%-14s %-18s %d/%d fights hit the ceiling"
					% [left_out, enc_id, hit, SEEDS])

	print("")
	print("%d fights. longest %d ticks (%.0f%% of budget) -- %s"
		% [fights, worst, 100.0 * float(worst) / float(CG.MAX_TICKS), worst_label])
	if capped == 0:
		print("no fight hit the ceiling. the halved budget is not truncating anything.")
	else:
		print("%d fights were cut off and reported as DRAW. the budget is too small." % capped)
	quit(0)

func _run(ids: Array, enc_id: StringName, s: int) -> CombatState:
	var party: Array[PawnData] = []
	for cid in ids:
		var c := StringName(cid)
		party.append(PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
		))
	var state := CombatSim.build(party, Registry.get_encounter(enc_id), s)
	CombatSim.run(state)
	return state
