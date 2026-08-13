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


func test_siege_masters_and_priests_fight_differently() -> void:
	_assert_pair_differs(&"siege_master", &"priest", 1)


func test_geysermancers_and_warriors_fight_differently() -> void:
	_assert_pair_differs(&"geysermancer", &"warrior", 1)


## Issue 2's acceptance criterion 6 asks to run the encounter across twenty
## seeds and paste the win count, expecting neither 0 nor 20. That assumes
## combat outcomes vary with the seed. They do not: nothing in Balance,
## DefaultBehavior or PlanInterpreter reads `CombatState.rng` (there is no
## damage roll, no dodge, no crit — CombatSim's own `_apply_action_effect` is
## pure arithmetic on `deps.attack_power`/`deps.damage_reduction`), so a fixed
## party against this fixed, hand-authored encounter produces the exact same
## outcome on every seed. Confirmed by running all 20 and getting 20/20, then
## 0/20, identically, while tuning. Flagged in TEAM_LOG for rook rather than
## silently reinterpreting the criterion: fixing it for real means either
## adding damage-roll variance somewhere sim-side (a Balance/SimDeps signature
## question, not mine to decide alone) or accepting that "seed" is inert until
## that lands.
##
## What this test checks instead, which is the tuning signal seed variance
## was standing in for: the room is winnable by a competent, varied party and
## losable by a poorly-built one. Both numbers below are still measured and
## pasted, just against party composition instead of seed.
func test_encounter_is_winnable_by_a_good_party_and_losable_by_a_weak_one() -> void:
	var encounter := Registry.get_encounter(&"floor1_room1")

	var strong: Array[StringName] = [&"warrior", &"priest", &"geysermancer", &"siege_master"]
	var weak: Array[StringName] = [&"geysermancer", &"geysermancer", &"siege_master", &"siege_master"]

	var strong_party: Array[PawnData] = []
	var weak_party: Array[PawnData] = []
	for i in strong.size():
		strong_party.append(PawnFactory.make_starter_pawn(strong[i], &"strong_%d" % i, String(strong[i])))
	for i in weak.size():
		weak_party.append(PawnFactory.make_starter_pawn(weak[i], &"weak_%d" % i, String(weak[i])))

	var strong_state := CombatSim.build(strong_party, encounter, 0)
	var strong_outcome := CombatSim.run(strong_state)
	var weak_state := CombatSim.build(weak_party, encounter, 0)
	var weak_outcome := CombatSim.run(weak_state)

	print("floor1_room1: balanced party (warrior/priest/geysermancer/siege_master) -> %s in %d ticks" % [CombatState.Outcome.keys()[strong_outcome], strong_state.tick])
	print("floor1_room1: glass-cannon party (2x geysermancer/2x siege_master, no tank, no healer) -> %s in %d ticks" % [CombatState.Outcome.keys()[weak_outcome], weak_state.tick])

	assert_eq(strong_outcome, CombatState.Outcome.PLAYER_WIN, "a balanced party should be able to win this room")
	assert_eq(weak_outcome, CombatState.Outcome.ENEMY_WIN, "an unbalanced glass-cannon party should be able to lose this room")
