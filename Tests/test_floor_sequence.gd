extends "res://Tests/TestCase.gd"


## Issue 729/730/732: the order of one floor's ten rooms, and the carry
## between them (damage persists, a fraction heals on arrival). No
## CombatSim.run here -- CombatSim.build is construction, not a fight, per
## Tests/test_no_test_runs_a_fight.gd.

const ALL_IDS := [
	&"floor1_room1", &"floor1_horde", &"floor1_ghoul_den", &"floor1_cover",
	&"floor1_hazard", &"floor1_chokepoint", &"floor1_sellsword",
	&"floor1_narrows_elite", &"floor1_rat_king", &"floor1_warden",
]

func test_ten_rooms_no_duplicates() -> void:
	var seq := FloorSequence.build(1234)
	assert_eq(seq.size(), 10)
	var seen := {}
	for id in seq:
		assert_true(not seen.has(id), "duplicate room %s" % id)
		seen[id] = true
	for id in ALL_IDS:
		assert_true(seen.has(id), "missing room %s" % id)

func test_warden_always_last() -> void:
	for s in range(20):
		var seq := FloorSequence.build(s)
		assert_eq(seq[9], &"floor1_warden", "seed %d" % s)

func test_rat_king_slot_5_or_6() -> void:
	for s in range(20):
		var seq := FloorSequence.build(s)
		var idx := seq.find(&"floor1_rat_king")
		assert_true(idx == 4 or idx == 5, "seed %d landed rat king at %d" % [s, idx])

func test_same_seed_same_order() -> void:
	assert_eq(FloorSequence.build(77), FloorSequence.build(77))

func test_different_seeds_usually_differ() -> void:
	var a := FloorSequence.build(1)
	var b := FloorSequence.build(2)
	assert_ne(a, b)

## Issue 732: damage carries, then the arrival heal fraction applies on top --
## replaces the old "no healing between rooms" assertion #729 shipped with,
## which #732's player ruling overturns.
func test_carry_into_carries_damage_then_heals_a_fraction() -> void:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w", "W")]
	var encounter := RoomLibrary.get_room(&"floor1_room1")
	var state := CombatSim.build(party, encounter, 1)
	var hp_max := state.unit(0).hp_max
	var run := FloorRun.new()
	run.record_result(&"w", 1, 0, true)
	FloorRun.carry_into(run, state, party)
	var expected := mini(hp_max, 1 + int(round(float(hp_max) * FloorRun.BETWEEN_ROOM_HEAL_FRACTION)))
	assert_eq(state.unit(0).hp, expected, "carried hp plus the arrival heal fraction")

func test_carry_into_keeps_dead_pawns_dead() -> void:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w", "W")]
	var encounter := RoomLibrary.get_room(&"floor1_room1")
	var state := CombatSim.build(party, encounter, 1)
	var run := FloorRun.new()
	run.record_result(&"w", 0, 0, false)
	FloorRun.carry_into(run, state, party)
	assert_false(state.unit(0).alive)
	assert_eq(state.unit(0).hp, 0)
