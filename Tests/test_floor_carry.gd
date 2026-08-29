extends "res://Tests/TestCase.gd"


## Issue 730/732/796: what a pawn carries from one room of a floor into the
## next -- damage persists, a fraction of the missing hp heals on arrival,
## death sticks. Moved here from `test_floor_sequence.gd` when #804 deleted
## `FloorSequence`; these test `FloorRun`, which survives it.

## Issue 796: damage carries, then half the MISSING hp is healed on top --
## replaces #732's flat fraction of max, which fully healed a lightly damaged
## party and made early rooms free.
func test_carry_into_carries_damage_then_heals_half_the_missing() -> void:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w", "W")]
	var encounter := RoomLibrary.get_room(&"floor1_room1")
	var state := CombatSim.build(party, encounter, 1)
	var hp_max := state.unit(0).hp_max
	var run := FloorRun.new()
	run.record_result(&"w", 1, 0, true)
	FloorRun.carry_into(run, state, party)
	var expected := mini(hp_max, 1 + int(round(float(hp_max - 1) * FloorRun.BETWEEN_ROOM_HEAL_MISSING_FRACTION)))
	assert_eq(state.unit(0).hp, expected, "carried hp plus half the missing hp")
	assert_true(state.unit(0).hp < hp_max, "a missing-fraction heal never reaches full")

## Issue 796: the negative half. A pawn that arrives at full hp is missing
## nothing, so it heals nothing and emits no event.
func test_carry_into_full_hp_pawn_heals_nothing() -> void:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w", "W")]
	var encounter := RoomLibrary.get_room(&"floor1_room1")
	var state := CombatSim.build(party, encounter, 1)
	var hp_max := state.unit(0).hp_max
	var run := FloorRun.new()
	run.record_result(&"w", hp_max, 0, true)
	var events_before := state.events.size()
	FloorRun.carry_into(run, state, party)
	assert_eq(state.unit(0).hp, hp_max)
	assert_eq(state.events.size(), events_before, "no event for no change")

func test_carry_into_keeps_dead_pawns_dead() -> void:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w", "W")]
	var encounter := RoomLibrary.get_room(&"floor1_room1")
	var state := CombatSim.build(party, encounter, 1)
	var run := FloorRun.new()
	run.record_result(&"w", 0, 0, false)
	FloorRun.carry_into(run, state, party)
	assert_false(state.unit(0).alive)
	assert_eq(state.unit(0).hp, 0)
