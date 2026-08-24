extends "res://Tests/TestCase.gd"

## Issue 543: one ungeared pawn against two base enemies, recorded exactly.
##
## **This file is the snapshot, not the rule.** The player's baseline -- every
## class wins, and no win is a stomp -- is a target the game does not currently
## meet, and half of why is #544 rather than a number. A target is an issue; what
## ships here is what the fight measures today, so any movement goes red.
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
const RECORDED := {
	&"warrior": {"wins": 10, "hp": [80, 77, 77, 80, 80, 80, 77, 80, 80, 80]},
	&"abomination": {"wins": 10, "hp": [81, 81, 81, 81, 93, 89, 96, 81, 81, 93]},
	&"siege_master": {"wins": 10, "hp": [68, 76, 68, 61, 61, 76, 68, 68, 68, 61]},
	&"geysermancer": {"wins": 10, "hp": [91, 91, 72, 54, 72, 91, 54, 82, 72, 72]},
	&"priest": {"wins": 7, "hp": [100, 100, 100, 100, 100, 100, 100]},
}

## The three classes #544 is about. A planless pawn is what `PartySelect`
## deploys, and these three stop attacking once a Goblin is inside 60% of their
## range, so they lose every seed.
const RANGED_CLASSES := [&"priest", &"geysermancer", &"siege_master"]

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


## #544, recorded so that fixing it goes red here and this file gets re-measured
## rather than quietly left describing a defect that no longer exists.
func test_planless_ranged_classes_still_lose_every_seed_because_of_544() -> void:
	for class_id in RANGED_CLASSES:
		var m := _measure(class_id, BASE_ENEMY, BASE_ENEMY_COUNT, false)
		assert_eq(m["wins"], 0,
			("%s now wins %d of %d planless. If #544 is fixed this is the good news and the "
			+ "recorded table above needs re-measuring; if it is not, something else moved.")
			% [class_id, m["wins"], SEEDS])


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
