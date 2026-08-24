extends "res://Tests/TestCase.gd"

## Issue 543: one ungeared pawn against two base enemies, recorded exactly.
##
## **This file is the snapshot, not the rule.** The player's baseline -- every
## class wins, and no win is a stomp -- is a target the game does not currently
## meet. A target is an issue; what ships here is what the fight measures today,
## so any movement goes red. Re-measured on #544, which is fixed.
##
## Ungeared is armour off and weapon kept: every basic attack is granted by a
## weapon, so a weaponless pawn has nothing to attack with.

const SEEDS := 10

## See #543 for why the Goblin: floor 1's first room is built out of them, it
## carries one action, and it is melee so no class gets a free approach. #542
## proposes a base monster profile; when it lands, read that rather than this id.
const BASE_ENEMY := &"goblin"
const BASE_ENEMY_COUNT := 2

## What the fight measures today, seed 0 to 9, preset plans and no armour:
## wins, then the pawn's remaining health on each win, in seed order. Exact
## rather than a tolerance, because the simulation is deterministic -- the same
## seed gives the same fight, so a range here would only hide movement.
## Re-measured on #544, which deleted `DefaultBehavior`'s automatic retreat.
## Warrior, Abomination and Geysermancer did not move; Siege Master and Priest
## did, because a preset plan still leaves movement to the fallback.
const RECORDED := {
	&"warrior": {"wins": 10, "hp": [80, 77, 77, 80, 80, 80, 77, 80, 80, 80]},
	&"abomination": {"wins": 10, "hp": [81, 81, 81, 81, 93, 89, 96, 81, 81, 93]},
	&"siege_master": {"wins": 10, "hp": [45, 61, 61, 45, 37, 68, 61, 53, 61, 45]},
	&"geysermancer": {"wins": 10, "hp": [91, 91, 72, 54, 72, 91, 54, 82, 72, 72]},
	&"priest": {"wins": 10, "hp": [100, 94, 94, 100, 100, 100, 100, 94, 100, 94]},
}

## The same fight with no plan rows at all, which is what `PartySelect` deploys.
## Recorded separately because it is the arm #544 was about: it read 0 wins for
## all three ranged classes and now reads what is below.
const RECORDED_PLANLESS := {
	&"warrior": {"wins": 10, "hp": [71, 84, 84, 71, 84, 84, 84, 74, 74, 84]},
	&"abomination": {"wins": 10, "hp": [93, 81, 81, 93, 81, 93, 74, 96, 81, 81]},
	&"siege_master": {"wins": 10, "hp": [76, 92, 92, 68, 76, 92, 61, 76, 92, 92]},
	&"geysermancer": {"wins": 0, "hp": []},
	&"priest": {"wins": 10, "hp": [56, 60, 56, 48, 53, 59, 44, 46, 66, 45]},
}

## Preset plans, not the planless fallback: a planless Siege Master never builds
## an engine, so that arm measures `DefaultBehavior` rather than the class.
func _ungeared(class_id: StringName, use_presets: bool = true) -> PawnData:
	var pawn := PawnFactory.make_preset_pawn(class_id, class_id, String(class_id)) if use_presets \
		else PawnFactory.make_starter_pawn(class_id, class_id, String(class_id))
	pawn.armor = null
	pawn.accessory = null
	return pawn

## Built here and never registered, so `Registry.all_encounter_ids()` does not
## move and the #540 sim fingerprint cannot be tripped by this file.
func _encounter(enemy_id: StringName, count: int) -> Encounter:
	var e := Encounter.new()
	e.id = &"baseline_1v2"
	var spawns: Array[Dictionary] = []
	for i in count:
		spawns.append({"enemy_id": enemy_id, "position": Vector2(150.0, -50.0 + 100.0 * float(i))})
	e.enemy_spawns = spawns
	e.party_spawns = [Vector2(-350.0, 0.0)]
	return e

## Wins, and the pawn's remaining health on each won fight, in seed order.
func _measure(class_id: StringName, enemy_id: StringName = BASE_ENEMY, count: int = BASE_ENEMY_COUNT, use_presets: bool = true) -> Dictionary:
	var e := _encounter(enemy_id, count)
	var wins := 0
	var win_hp: Array[int] = []
	for s in SEEDS:
		var party: Array[PawnData] = [_ungeared(class_id, use_presets)]
		var state := CombatSim.build(party, e, s)
		if CombatSim.run(state) != CombatState.Outcome.PLAYER_WIN:
			continue
		wins += 1
		win_hp.append(_pawn_hp_percent(state))
	return {"wins": wins, "win_hp": win_hp}

func _pawn_hp_percent(state: CombatState) -> int:
	for u in state.units:
		if u.team == CG.Team.PLAYER and u.pawn != null:
			return int(round(100.0 * float(maxi(0, u.hp)) / float(maxi(1, u.hp_max))))
	return 0


## The snapshot. Red the day any of it moves, in either direction.
func test_the_one_versus_two_baseline_is_what_it_was_recorded_as() -> void:
	for class_id in RECORDED:
		var m := _measure(class_id)
		var expected: Dictionary = RECORDED[class_id]
		assert_eq(m["wins"], expected["wins"], "%s wins against %d %s moved" % [class_id, BASE_ENEMY_COUNT, BASE_ENEMY])
		assert_eq(m["win_hp"], expected["hp"], "%s remaining health on its wins moved" % class_id)


## The planless arm, the same way. **The Geysermancer's 0 is not #544 coming
## back**: it fires 7 times in the fight it used to fire twice in, and still
## loses on 98 hp with no plan telling it what to do with its kit. That is a
## separate finding, reported and not tuned.
func test_the_planless_baseline_is_what_it_was_recorded_as() -> void:
	for class_id in RECORDED_PLANLESS:
		var m := _measure(class_id, BASE_ENEMY, BASE_ENEMY_COUNT, false)
		var expected: Dictionary = RECORDED_PLANLESS[class_id]
		assert_eq(m["wins"], expected["wins"], "%s planless wins moved" % class_id)
		assert_eq(m["win_hp"], expected["hp"], "%s planless remaining health on its wins moved" % class_id)


## #544's own proof, kept where it goes red rather than only in a probe: the
## fallback stopped firing once a Goblin was inside 60% of a ranged pawn's own
## range, which cost a Geysermancer every action after tick 81 of 279.
func test_a_planless_ranged_pawn_keeps_attacking_when_crowded() -> void:
	var e := _encounter(BASE_ENEMY, BASE_ENEMY_COUNT)
	var party: Array[PawnData] = [_ungeared(&"geysermancer", false)]
	var state := CombatSim.build(party, e, 0)
	var pawn_id := -1
	for u in state.units:
		if u.pawn != null:
			pawn_id = u.id
	CombatSim.run(state)
	var started := 0
	for ev in state.events:
		if ev.kind == CG.EventKind.ACTION_START and ev.source_id == pawn_id:
			started += 1
	assert_true(started > 2,
		"a planless Geysermancer started %d actions in %d ticks; 2 is #544's automatic retreat back"
		% [started, state.tick])


## A snapshot of a measurement that cannot fail is worth nothing, so both
## directions are proved. A lone ungeared Priest loses to The Warden every seed.
func test_the_measurement_can_read_a_loss() -> void:
	var m := _measure(&"priest", &"the_warden", 1)
	assert_eq(m["wins"], 0, "a lone ungeared Priest should not beat The Warden")


## And the other direction: it reads a win, and reads the health left over.
func test_the_measurement_can_read_a_win_and_its_margin() -> void:
	var m := _measure(&"warrior", &"rat", 1)
	assert_eq(m["wins"], SEEDS, "a Warrior should beat one Rat on every seed")
	for pct in m["win_hp"]:
		assert_true(pct > 0 and pct <= 100, "a won fight should report a real remaining-health percentage, got %d" % pct)
