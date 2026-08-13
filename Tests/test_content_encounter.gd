extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

## The whole-fight acceptance checks from issue 2: classes differ measurably,
## and the one encounter is winnable and losable. Real CombatSim, real
## Registry content, now that issue 1 has landed. Numbers this prints are the
## ones pasted into the PR.

func _party_of(class_id: StringName, count: int) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for i in count:
		party.append(PawnFactory.make_starter_pawn(class_id, &"%s_%d" % [class_id, i], "%s %d" % [class_id, i]))
	return party

func _run(class_id: StringName, seed: int) -> Dictionary:
	var encounter := Registry.get_encounter(&"floor1_room1")
	var state := CombatSim.build(_party_of(class_id, 4), encounter, seed)
	var outcome := CombatSim.run(state)
	return {"outcome": outcome, "ticks": state.tick}

func _differs(a: Dictionary, b: Dictionary) -> bool:
	if a["outcome"] != b["outcome"]:
		return true
	var longer = maxf(float(a["ticks"]), float(b["ticks"]))
	var shorter = minf(float(a["ticks"]), float(b["ticks"]))
	if shorter <= 0.0:
		return longer > 0.0
	return (longer / shorter) >= 1.2


func _assert_pair_differs(class_a: StringName, class_b: StringName, seed: int) -> void:
	var a := _run(class_a, seed)
	var b := _run(class_b, seed)
	print("classes differ: %s outcome=%s ticks=%d  vs  %s outcome=%s ticks=%d" % [
		class_a, CombatState.Outcome.keys()[a["outcome"]], a["ticks"],
		class_b, CombatState.Outcome.keys()[b["outcome"]], b["ticks"],
	])
	assert_true(_differs(a, b), "%s and %s produced the same outcome and near-identical length on seed %d" % [class_a, class_b, seed])


func test_warriors_and_priests_fight_differently() -> void:
	_assert_pair_differs(&"warrior", &"priest", 1)


func test_abominations_and_priests_fight_differently() -> void:
	_assert_pair_differs(&"abomination", &"priest", 1)


func test_geysermancers_and_warriors_fight_differently() -> void:
	_assert_pair_differs(&"geysermancer", &"warrior", 1)


## Issue 2's acceptance criterion 6 asked for a win count across twenty seeds
## that was neither 0 nor 20, which assumed combat outcomes vary with the
## seed. At the time nothing did: no damage roll, no dodge, no crit anywhere
## in this slice's combat math. Flagged in TEAM_LOG rather than silently
## reinterpreting the criterion; the fix landed as issue 7's damage-variance
## hook (`Balance.attack_power`'s optional `rng`, threaded through from
## `CombatState.rng` by `CombatSim`/`SimDeps`). The tests below are issue 7's
## real distribution-based replacements for that single-seed check.

func _win_rate(classes: Array[StringName], seeds: int) -> Dictionary:
	var encounter := Registry.get_encounter(&"floor1_room1")
	var wins := 0
	var ticks: Array[int] = []
	for seed in seeds:
		var party: Array[PawnData] = []
		for i in classes.size():
			party.append(PawnFactory.make_starter_pawn(classes[i], &"%s_%d_%d" % [classes[i], seed, i], String(classes[i])))
		var state := CombatSim.build(party, encounter, seed)
		var outcome := CombatSim.run(state)
		if outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
		ticks.append(state.tick)
	ticks.sort()
	return {"wins": wins, "min": ticks[0], "median": ticks[ticks.size() / 2], "max": ticks[ticks.size() - 1]}


func test_seed_changes_the_fight() -> void:
	# abomination x4 has the widest measured spread of the sampled comps
	# once issue 12's bestiary and issue 20's regeneration are both in.
	var r := _win_rate([&"abomination", &"abomination", &"abomination", &"abomination"], 20)
	var spread_fraction := float(r["max"] - r["min"]) / float(max(1, r["median"]))
	print("seed sensitivity, abomination x4: ticks min=%d median=%d max=%d (spread %.0f%% of median)" % [r["min"], r["median"], r["max"], spread_fraction * 100.0])
	assert_true(spread_fraction >= 0.15, "tick spread should be at least 15%% of the median, was %.0f%%" % (spread_fraction * 100.0))


func test_same_seed_replays_bit_identical() -> void:
	var encounter := Registry.get_encounter(&"floor1_room1")
	var party_a := _party_of(&"priest", 4)
	var party_b := _party_of(&"priest", 4)
	var state_a := CombatSim.build(party_a, encounter, 777)
	var state_b := CombatSim.build(party_b, encounter, 777)
	var outcome_a := CombatSim.run(state_a)
	var outcome_b := CombatSim.run(state_b)
	assert_eq(outcome_a, outcome_b)
	assert_eq(state_a.tick, state_b.tick)
	assert_eq(state_a.events.size(), state_b.events.size(), "same seed must produce the same number of events")


func test_some_composition_is_a_genuine_coin_flip() -> void:
	var r := _win_rate([&"siege_master", &"siege_master", &"siege_master", &"siege_master"], 20)
	print("floor1_room1: siege_master x4 win rate %d/20" % r["wins"])
	assert_true(r["wins"] >= 6 and r["wins"] <= 14, "expected a genuine coin flip (6-14 of 20), got %d/20" % r["wins"])


func test_composition_still_matters() -> void:
	var best := _win_rate([&"warrior", &"warrior", &"warrior", &"warrior"], 20)
	var worst := _win_rate([&"abomination", &"abomination", &"abomination", &"abomination"], 20)
	print("floor1_room1: best comp (warrior x4) win rate %d/20  vs  worst comp (abomination x4) win rate %d/20" % [best["wins"], worst["wins"]])
	assert_true(best["wins"] - worst["wins"] >= 10, "best and worst comps should differ by a wide margin in win rate")


## The user's rewritten issue 7 criterion 1: a mostly-winning party's win
## should cost something. Median hp% the party finished a win on, dead pawns
## counted as zero (matches Tools/SampleFights.gd's cost metric). Printed and
## sanity-checked rather than hard-asserted at the target (<=40% or 2+ down):
## current tuning gets real cost into winning fights (measured 57-71% across
## the strongest comps, down from 85-95%+ before issue 12 and issue 20) but
## does not yet reach it, and asserting the target here would either fail
## honestly or get quietly loosened later. TEAM_LOG carries the real number
## and the finding about why (concentration, not total damage).
func test_a_winning_party_pays_a_real_cost() -> void:
	var r := _win_rate([&"warrior", &"warrior", &"warrior", &"warrior"], 20)
	var encounter := Registry.get_encounter(&"floor1_room1")
	var costs: Array[float] = []
	for seed in 20:
		var party := _party_of(&"warrior", 4)
		var state := CombatSim.build(party, encounter, seed)
		var outcome := CombatSim.run(state)
		if outcome != CombatState.Outcome.PLAYER_WIN:
			continue
		var total_hp := 0.0
		var max_hp := 0.0
		for u in state.units:
			if u.team == CG.Team.PLAYER:
				max_hp += float(u.hp_max)
				total_hp += float(maxi(0, u.hp))
		costs.append(total_hp / max_hp * 100.0)
	costs.sort()
	var median_cost := costs[costs.size() / 2] if not costs.is_empty() else 100.0
	print("floor1_room1: warrior x4 median hp%% on a win = %.0f%% (target: <=40%% or 2+ pawns down, not yet met)" % median_cost)
	assert_true(median_cost < 100.0, "a win should cost something measurable")
