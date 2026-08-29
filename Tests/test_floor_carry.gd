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

## Issue 802. The cadence and the returning fraction are static vars so the
## sweep can set them from the command line; every test below puts back what
## it found, or the next test in this file inherits a swept setting.
func _arrive_dead(room_index: int) -> CombatState:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w", "W")]
	var state := CombatSim.build(party, RoomLibrary.get_room(&"floor1_room1"), 1)
	var run := FloorRun.new()
	run.record_result(&"w", 0, 0, false)
	FloorRun.carry_into(run, state, party, room_index)
	return state

func _set_revive(every: int, fraction: float, camp: bool = false) -> Array:
	var was := [FloorRun.REVIVE_EVERY_N_ROOMS, FloorRun.REVIVE_AT_HP_FRACTION,
		FloorRun.REVIVE_ONCE_ON_TWO_DOWN]
	FloorRun.REVIVE_EVERY_N_ROOMS = every
	FloorRun.REVIVE_AT_HP_FRACTION = fraction
	FloorRun.REVIVE_ONCE_ON_TWO_DOWN = camp
	return was

func _restore_revive(was: Array) -> void:
	FloorRun.REVIVE_EVERY_N_ROOMS = was[0]
	FloorRun.REVIVE_AT_HP_FRACTION = was[1]
	FloorRun.REVIVE_ONCE_ON_TWO_DOWN = was[2]

## Issue 802 shipped the camp at 50%: arm A spent it in 35 of 40 runs and
## still cleared 0 of 40, arm B cleared 12. The fixed cadence ships off.
func test_shipped_revive_settings() -> void:
	assert_true(FloorRun.REVIVE_ONCE_ON_TWO_DOWN)
	assert_eq(FloorRun.REVIVE_AT_HP_FRACTION, 0.5)
	assert_eq(FloorRun.REVIVE_EVERY_N_ROOMS, 0)

## Two dead, not one: #797 put the cliff at the second death, so that is the
## moment a saved camp is worth spending.
func _pair() -> Array[PawnData]:
	var party: Array[PawnData] = [
		PawnFactory.make_starter_pawn(&"warrior", &"w", "W"),
		PawnFactory.make_starter_pawn(&"priest", &"p", "P")]
	return party

func test_camp_waits_for_the_second_death_then_spends_itself() -> void:
	var was := _set_revive(3, 0.25, true)
	var party := _pair()
	var run := FloorRun.new()
	run.record_result(&"w", 0, 0, false)
	assert_eq(run.down_count(party), 1)
	assert_false(FloorRun.should_revive(run, party, 3),
		"one down is not the cliff, and the cadence must not fire either")
	run.record_result(&"p", 0, 0, false)
	assert_true(FloorRun.should_revive(run, party, 1), "two down spends the camp")
	var state := CombatSim.build(party, RoomLibrary.get_room(&"floor1_room1"), 1)
	FloorRun.carry_into(run, state, party, 1)
	assert_true(run.revive_used)
	assert_true(state.unit(0).alive, "both come back")
	assert_true(state.unit(1).alive)
	assert_false(FloorRun.should_revive(run, party, 4), "one camp per floor, and it is spent")
	_restore_revive(was)

func test_camp_never_fires_in_the_first_room() -> void:
	var was := _set_revive(0, 0.25, true)
	var party := _pair()
	var run := FloorRun.new()
	run.record_result(&"w", 0, 0, false)
	run.record_result(&"p", 0, 0, false)
	assert_false(FloorRun.should_revive(run, party, 0))
	_restore_revive(was)

func test_revive_cadence_zero_never_revives() -> void:
	var was := _set_revive(0, 0.25)
	assert_false(FloorRun.revives_on_arrival(1))
	assert_false(FloorRun.revives_on_arrival(9))
	assert_false(_arrive_dead(9).unit(0).alive, "cadence 0 is pre-802 behaviour: dead stays dead")
	_restore_revive(was)

func test_revive_never_fires_in_the_first_room() -> void:
	var was := _set_revive(1, 0.25)
	assert_false(FloorRun.revives_on_arrival(0), "nobody has died before room 0")
	assert_false(_arrive_dead(0).unit(0).alive)
	_restore_revive(was)

func test_revive_returns_a_pawn_at_its_fraction_and_no_arrival_heal() -> void:
	var was := _set_revive(1, 0.25)
	var state := _arrive_dead(1)
	var unit := state.unit(0)
	var expected := maxi(1, int(round(float(unit.hp_max) * 0.25)))
	assert_true(unit.alive, "a revive room brings a fallen pawn back")
	assert_eq(unit.hp, expected, "exactly the fraction: the arrival heal must not stack on top")
	assert_eq(unit.resource, 0, "a revived pawn arrives with no resource")
	_restore_revive(was)

func test_revive_every_third_room_skips_the_rooms_between() -> void:
	var was := _set_revive(3, 0.25)
	assert_false(FloorRun.revives_on_arrival(1))
	assert_false(FloorRun.revives_on_arrival(2))
	assert_true(FloorRun.revives_on_arrival(3))
	assert_true(FloorRun.revives_on_arrival(6))
	assert_false(_arrive_dead(2).unit(0).alive, "room 2 is not a checkpoint")
	assert_true(_arrive_dead(3).unit(0).alive, "room 3 is")
	_restore_revive(was)
