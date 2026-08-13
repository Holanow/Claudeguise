extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

## The whole-fight acceptance checks from issues 2 and 7. Real CombatSim, real
## Registry content. Reference compositions here are re-picked whenever a
## balance-affecting fix lands (14a, regeneration, the bestiary, focus_bias,
## issue 22's plan-affordability fix all moved this table) — see TEAM_LOG for
## the history. What matters is the shape (some comp always loses, some comp
## is a genuine toss-up, the best comp costs the party something to win), not
## any specific class staying "the" reference forever.

func _party_of(class_id: StringName, count: int) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for i in count:
		party.append(PawnFactory.make_starter_pawn(class_id, &"%s_%d" % [class_id, i], "%s %d" % [class_id, i]))
	return party

func _run(class_id: StringName, seed: int) -> Dictionary:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
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


func test_geysermancers_and_warriors_fight_differently() -> void:
	_assert_pair_differs(&"geysermancer", &"warrior", 1)


func test_geysermancers_and_priests_fight_differently() -> void:
	_assert_pair_differs(&"geysermancer", &"priest", 1)


func test_geysermancers_and_siege_masters_fight_differently() -> void:
	_assert_pair_differs(&"geysermancer", &"siege_master", 1)


## Issue 2's acceptance criterion 6 asked for a win count across twenty seeds
## that was neither 0 nor 20, which assumed combat outcomes vary with the
## seed. At the time nothing did. The fix landed as issue 7's damage-variance
## hook. The tests below are issue 7's real distribution-based replacements
## for that single-seed check.

func _win_rate(classes: Array[StringName], seeds: int) -> Dictionary:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	var wins := 0
	var ticks: Array[int] = []
	var costs: Array[float] = []
	for seed in seeds:
		var party: Array[PawnData] = []
		for i in classes.size():
			party.append(PawnFactory.make_starter_pawn(classes[i], &"%s_%d_%d" % [classes[i], seed, i], String(classes[i])))
		var state := CombatSim.build(party, encounter, seed)
		var outcome := CombatSim.run(state)
		ticks.append(state.tick)
		if outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
			var total_hp := 0.0
			var max_hp := 0.0
			for u in state.units:
				if u.team == CG.Team.PLAYER:
					max_hp += float(u.hp_max)
					total_hp += float(maxi(0, u.hp))
			costs.append(total_hp / max_hp * 100.0)
	ticks.sort()
	costs.sort()
	var median_cost := costs[costs.size() / 2] if not costs.is_empty() else -1.0
	return {"wins": wins, "min": ticks[0], "median": ticks[ticks.size() / 2], "max": ticks[ticks.size() - 1], "median_cost": median_cost}


func test_seed_changes_the_fight() -> void:
	# geysermancer x4 has the widest measured spread of the sampled comps.
	var r := _win_rate([&"geysermancer", &"geysermancer", &"geysermancer", &"geysermancer"], 20)
	var spread_fraction := float(r["max"] - r["min"]) / float(max(1, r["median"]))
	print("seed sensitivity, geysermancer x4: ticks min=%d median=%d max=%d (spread %.0f%% of median)" % [r["min"], r["median"], r["max"], spread_fraction * 100.0])
	assert_true(spread_fraction >= 0.15, "tick spread should be at least 15%% of the median, was %.0f%%" % (spread_fraction * 100.0))


func test_same_seed_replays_bit_identical() -> void:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
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
	var r := _win_rate([&"abomination", &"abomination", &"abomination", &"abomination"], 20)
	print("floor1_room1: abomination x4 win rate %d/20" % r["wins"])
	assert_true(r["wins"] >= 6 and r["wins"] <= 14, "expected a genuine coin flip (6-14 of 20), got %d/20" % r["wins"])


func test_composition_still_matters() -> void:
	var best := _win_rate([&"siege_master", &"siege_master", &"siege_master", &"siege_master"], 20)
	var worst := _win_rate([&"geysermancer", &"geysermancer", &"geysermancer", &"geysermancer"], 20)
	print("floor1_room1: best comp (siege_master x4) win rate %d/20  vs  worst comp (geysermancer x4) win rate %d/20" % [best["wins"], worst["wins"]])
	assert_true(best["wins"] - worst["wins"] >= 10, "best and worst comps should differ by a wide margin in win rate")


## The user's rewritten issue 7 criterion 1, met for real now: a mostly-
## winning party's win costs something, measured as the median hp% the party
## finished on across its wins, dead pawns counted as zero. Target: <=40% or
## 2+ pawns down. issue 22 (plan affordability) and EnemyDef.focus_bias
## (concentration) together are what finally closed this — see TEAM_LOG for
## the full trace of why numbers alone never did.
func test_a_winning_party_pays_a_real_cost() -> void:
	var r := _win_rate([&"siege_master", &"geysermancer", &"priest", &"warrior"], 20)
	print("floor1_room1: siege_master/geysermancer/priest/warrior win rate %d/20, median hp%% on a win = %.0f%%" % [r["wins"], r["median_cost"]])
	assert_true(r["wins"] >= 17, "this comp should still win most of the time")
	assert_true(r["median_cost"] >= 0.0 and r["median_cost"] <= 40.0, "median cost on a win should be <=40%%, was %.0f%%" % r["median_cost"])


## Issue 13b's cover room: same lever the wall would have tested (terrain
## denying a party that wins by standing at range), against a room that
## doesn't hit the movement-corner defect below. If a pillar were decoration,
## siege_master x4 -- issue 24's free-win composition -- would look the same
## with and without it, since nothing else about the room changes its range
## or hp.
func test_cover_changes_the_fight_for_a_pure_ranged_party() -> void:
	var open_room := Registry.get_encounter(&"floor1_room1")
	var cover := Registry.get_encounter(&"floor1_cover")
	assert_not_null(open_room)
	assert_not_null(cover)
	assert_true(cover.terrain.size() > 0, "floor1_cover should carry pillars")

	var differs := false
	for seed in 5:
		var state_open := CombatSim.build(_party_of(&"siege_master", 4), open_room, seed)
		CombatSim.run(state_open)
		var state_cover := CombatSim.build(_party_of(&"siege_master", 4), cover, seed)
		CombatSim.run(state_cover)
		print("cover seed %d: open room ticks=%d  vs  cover room ticks=%d" % [seed, state_open.tick, state_cover.tick])
		if _differs({"outcome": state_open.outcome, "ticks": state_open.tick}, {"outcome": state_cover.outcome, "ticks": state_cover.tick}):
			differs = true
	assert_true(differs, "floor1_cover's pillars should change the fight on at least one of 5 seeds, or they are decoration")


## Issue 34: `floor1_chokepoint` resolves now instead of drawing. It was pulled
## from the registry when it stalled every fight to the 3600-tick cap (issue
## 13b), then restored once the decide-time line-of-sight check came back
## (issue 34 -- a unit needs a reason to walk toward a target it can see is
## blocked, not just a movement fix for the corner it walks around). Checked
## directly rather than inferred from a win/loss count: most seeds should
## finish well under the tick cap.
func test_the_chokepoint_room_resolves_instead_of_drawing() -> void:
	var chokepoint := Registry.get_encounter(&"floor1_chokepoint")
	assert_not_null(chokepoint)
	var draws := 0
	for seed in 10:
		var state := CombatSim.build(_party_of(&"siege_master", 4), chokepoint, seed)
		CombatSim.run(state)
		if state.outcome == CombatState.Outcome.UNRESOLVED:
			draws += 1
	assert_true(draws <= 2, "expected floor1_chokepoint to resolve most fights, got %d/10 draws" % draws)
