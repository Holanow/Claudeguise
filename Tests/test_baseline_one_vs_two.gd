extends "res://Tests/TestCase.gd"

## Issue 543, the player's baseline: one ungeared pawn of any class beats two
## base enemies, and does not stomp them.
##
## Ungeared is armour off and weapon kept. A weaponless pawn has no basic
## attack at all -- every one is granted by a weapon -- so the literal reading
## was never testable.
##
## The encounter is built here and never registered, so
## `Registry.all_encounter_ids()` does not move and the #540 sim fingerprint
## cannot be tripped by this file.

const SEEDS := 10

## See #543 for why the Goblin: floor 1's first room is built out of them, it
## carries one action, and it is melee so no class gets a free approach. #542
## proposes a base monster profile; when it lands, read that rather than this id.
const BASE_ENEMY := &"goblin"
const BASE_ENEMY_COUNT := 2

## Remaining health at the end of a won fight, as a fraction of the pawn's own
## maximum. The player's, 2026-08-24: squishier pawns finish at 30% or less,
## tankier ones at 60%. Above the ceiling is the stomp.
const STOMP_CEILING := {
	&"warrior": 0.60,
	&"abomination": 0.60,
	&"siege_master": 0.30,
	&"priest": 0.30,
	&"geysermancer": 0.30,
}

## Preset plans, not the planless fallback. A planless Siege Master never builds
## an engine and a planless ranged pawn stops attacking entirely (#543), so the
## fallback arm measures `DefaultBehavior` rather than the class.
func _ungeared(class_id: StringName) -> PawnData:
	var pawn := PawnFactory.make_preset_pawn(class_id, class_id, String(class_id))
	pawn.armor = null
	pawn.accessory = null
	return pawn

func _encounter() -> Encounter:
	var e := Encounter.new()
	e.id = &"baseline_1v2"
	var spawns: Array[Dictionary] = []
	for i in BASE_ENEMY_COUNT:
		spawns.append({
			"enemy_id": BASE_ENEMY,
			"position": Vector2(150.0, -50.0 + 100.0 * float(i)),
		})
	e.enemy_spawns = spawns
	e.party_spawns = [Vector2(-350.0, 0.0)]
	return e

## Wins, and the pawn's remaining health percentage on each won fight.
func _measure(class_id: StringName, enemy_id: StringName = BASE_ENEMY, count: int = BASE_ENEMY_COUNT) -> Dictionary:
	var e := _encounter()
	if enemy_id != BASE_ENEMY or count != BASE_ENEMY_COUNT:
		var spawns: Array[Dictionary] = []
		for i in count:
			spawns.append({"enemy_id": enemy_id, "position": Vector2(150.0, -50.0 + 100.0 * float(i))})
		e.enemy_spawns = spawns
	var wins := 0
	var win_hp: Array[int] = []
	for s in SEEDS:
		var party: Array[PawnData] = [_ungeared(class_id)]
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

func _above_ceiling(class_id: StringName, win_hp: Array[int]) -> int:
	var ceiling := float(STOMP_CEILING[class_id]) * 100.0
	var n := 0
	for pct in win_hp:
		if float(pct) > ceiling:
			n += 1
	return n


## The first half. Every class wins every seed: "reliably, not 11 of 20".
func test_every_class_beats_two_base_enemies_on_every_seed() -> void:
	for class_id in STOMP_CEILING:
		var m := _measure(class_id)
		assert_eq(m["wins"], SEEDS, "%s won %d of %d against %d %s" % [
			class_id, m["wins"], SEEDS, BASE_ENEMY_COUNT, BASE_ENEMY,
		])


## The second half, and it is the one a "wins" assertion passes without. A
## walkover is the failure the player named, so a win above the class's
## remaining-health ceiling fails as loudly as a loss.
func test_no_class_stomps_two_base_enemies() -> void:
	for class_id in STOMP_CEILING:
		var m := _measure(class_id)
		var win_hp: Array[int] = m["win_hp"]
		if win_hp.is_empty():
			continue
		var over := _above_ceiling(class_id, win_hp)
		assert_eq(over, 0, "%s finished above its %d%% ceiling on %d of %d wins (%s)" % [
			class_id, int(round(float(STOMP_CEILING[class_id]) * 100.0)), over, win_hp.size(), str(win_hp),
		])


## The negative for the first half: the win assertion has to be able to fail.
## One Warden is not two Goblins and no ungeared pawn survives it.
func test_the_win_half_can_fail() -> void:
	var m := _measure(&"priest", &"the_warden", 1)
	assert_eq(m["wins"], 0, "a lone ungeared Priest should not beat The Warden; the win half cannot fail")


## The negative for the second half: the anti-stomp assertion has to be able to
## fire. One Rat is a walkover for a Warrior by construction.
func test_the_stomp_half_can_fire() -> void:
	var m := _measure(&"warrior", &"rat", 1)
	assert_true(m["wins"] > 0, "a Warrior should beat one Rat")
	assert_true(_above_ceiling(&"warrior", m["win_hp"]) > 0,
		"a Warrior beating one Rat must read as a stomp, or the anti-stomp half cannot fire at all")
