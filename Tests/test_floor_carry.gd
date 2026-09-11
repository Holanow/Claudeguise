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

## Issue 796: the negative half. A pawn that arrives full is missing nothing, so
## it heals nothing and emits no event. Issue 868: full RESOURCE too, or the
## arrival recovery has something to give and this counts its event.
func test_carry_into_full_hp_pawn_heals_nothing() -> void:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w", "W")]
	var encounter := RoomLibrary.get_room(&"floor1_room1")
	var state := CombatSim.build(party, encounter, 1)
	var hp_max := state.unit(0).hp_max
	var run := FloorRun.new()
	run.record_result(&"w", hp_max, state.unit(0).resource_max, true)
	var events_before := state.events.size()
	FloorRun.carry_into(run, state, party)
	assert_eq(state.unit(0).hp, hp_max)
	assert_eq(state.events.size(), events_before, "no event for no change")

## Issue 868: `Balance.between_room_resource_recover` was authored at 0.50 and
## never called by anything, which is why nothing was red. These four go through
## `carry_into`, so they fail if the recovery is written and never wired.
func _arrive_with(resource: int, heal: bool = true) -> CombatState:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"priest", &"p", "P")]
	var state := CombatSim.build(party, RoomLibrary.get_room(&"floor1_room1"), 1)
	var run := FloorRun.new()
	run.record_result(&"p", state.unit(0).hp_max, resource, true)
	FloorRun.carry_into(run, state, party, 0, null, heal)
	return state

func _resource_events(state: CombatState) -> Array[CombatEvent]:
	var out: Array[CombatEvent] = []
	for e in state.events:
		if e.kind == CG.EventKind.RESOURCE_GAINED:
			out.append(e)
	return out

func test_carry_into_recovers_half_the_missing_resource() -> void:
	var state := _arrive_with(0)
	var unit := state.unit(0)
	assert_true(unit.resource_max > 0, "a Priest has a pool to recover into")
	var expected := int(round(float(unit.resource_max) * FloorRun.BETWEEN_ROOM_RESOURCE_MISSING_FRACTION))
	assert_eq(unit.resource, expected, "half the missing resource, as authored in #868")
	assert_true(unit.resource < unit.resource_max, "a missing-fraction recovery never reaches full")
	var said := _resource_events(state)
	assert_eq(said.size(), 1, "the player is told, in the log, that it came back")
	assert_eq(said[0].source_id, -1, "nobody cast it, the same mark the arrival heal carries")
	assert_eq(said[0].amount, expected)

func test_carry_into_full_resource_pawn_recovers_nothing() -> void:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"priest", &"p", "P")]
	var state := CombatSim.build(party, RoomLibrary.get_room(&"floor1_room1"), 1)
	var full := state.unit(0).resource_max
	var run := FloorRun.new()
	run.record_result(&"p", state.unit(0).hp_max, full, true)
	FloorRun.carry_into(run, state, party)
	assert_eq(state.unit(0).resource, full, "never above its own pool")
	assert_eq(_resource_events(state).size(), 0, "no event for no change")

## Issue 805's pacing exploit, which resource has exactly as much of as hp did:
## without this, walking between two cleared rooms refills a caster for free.
func test_walking_back_into_a_cleared_room_does_not_recover_resource() -> void:
	var state := _arrive_with(3, false)
	assert_eq(state.unit(0).resource, 3, "the carried resource, and nothing on top of it")
	assert_eq(_resource_events(state).size(), 0)

## Issue 802: a revived pawn comes back with no resource and does not also take
## the arrival recovery in the same room, the same rule its hp already follows.
func test_a_revived_pawn_takes_no_arrival_recovery() -> void:
	var was := _set_revive(0, 0.5, true)
	var party := _pair()
	var run := FloorRun.new()
	run.record_result(&"w", 0, 0, false)
	run.record_result(&"p", 0, 0, false)
	var state := CombatSim.build(party, RoomLibrary.get_room(&"floor1_room1"), 1)
	FloorRun.carry_into(run, state, party, 1, null, true, _proxy_revive, _revive_every)
	assert_true(state.unit(1).alive, "the camp brought it back")
	assert_eq(state.unit(1).resource, 0, "and it comes back with an empty pool")
	assert_eq(_resource_events(state).size(), 0)
	_restore_revive(was)

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
	FloorRun.carry_into(run, state, party, room_index, null, true, _proxy_revive, _revive_every)
	return state

## Issues 908 and 924: the two-down proxy and the fixed cadence are arms passed
## per call now, not constants on FloorRun, so this fixture carries them and
## hands them to the call under test.
var _proxy_revive: bool = true
var _revive_every: int = 0

func _set_revive(every: int, fraction: float, camp: bool = false) -> Array:
	var was := [_revive_every, FloorRun.REVIVE_AT_HP_FRACTION, _proxy_revive]
	_revive_every = every
	FloorRun.REVIVE_AT_HP_FRACTION = fraction
	_proxy_revive = camp
	return was

func _restore_revive(was: Array) -> void:
	_revive_every = was[0]
	FloorRun.REVIVE_AT_HP_FRACTION = was[1]
	_proxy_revive = was[2]

## Issue 803 moved the live floor onto the camp room, so the fraction is what
## the game ships and the other two are the arms a sweep compares it against,
## which issues 908 and 924 moved to `Tools/ReviveArgs.gd` to say so.
func test_shipped_revive_settings() -> void:
	assert_eq(FloorRun.REVIVE_AT_HP_FRACTION, 0.5)
	assert_true(ReviveArgs.ONCE_ON_TWO_DOWN, "the comparison arm ships on")
	assert_eq(ReviveArgs.EVERY_N_ROOMS, 0, "the cadence arm ships off")

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
	assert_false(FloorRun.should_revive(run, party, 3, null, _proxy_revive, _revive_every),
		"one down is not the cliff, and the cadence must not fire either")
	run.record_result(&"p", 0, 0, false)
	assert_true(FloorRun.should_revive(run, party, 1, null, _proxy_revive, _revive_every), "two down spends the camp")
	var state := CombatSim.build(party, RoomLibrary.get_room(&"floor1_room1"), 1)
	FloorRun.carry_into(run, state, party, 1, null, true, _proxy_revive, _revive_every)
	assert_true(run.revive_used)
	assert_true(state.unit(0).alive, "both come back")
	assert_true(state.unit(1).alive)
	assert_false(FloorRun.should_revive(run, party, 4, null, _proxy_revive, _revive_every),
		"one camp per floor, and it is spent")
	_restore_revive(was)

func test_camp_never_fires_in_the_first_room() -> void:
	var was := _set_revive(0, 0.25, true)
	var party := _pair()
	var run := FloorRun.new()
	run.record_result(&"w", 0, 0, false)
	run.record_result(&"p", 0, 0, false)
	assert_false(FloorRun.should_revive(run, party, 0, null, _proxy_revive, _revive_every))
	_restore_revive(was)

func test_revive_cadence_zero_never_revives() -> void:
	var was := _set_revive(0, 0.25)
	assert_false(FloorRun.revives_on_arrival(1, _revive_every))
	assert_false(FloorRun.revives_on_arrival(9, _revive_every))
	assert_false(_arrive_dead(9).unit(0).alive, "cadence 0 is pre-802 behaviour: dead stays dead")
	_restore_revive(was)

func test_revive_never_fires_in_the_first_room() -> void:
	var was := _set_revive(1, 0.25)
	assert_false(FloorRun.revives_on_arrival(0, _revive_every), "nobody has died before room 0")
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
	assert_false(FloorRun.revives_on_arrival(1, _revive_every))
	assert_false(FloorRun.revives_on_arrival(2, _revive_every))
	assert_true(FloorRun.revives_on_arrival(3, _revive_every))
	assert_true(FloorRun.revives_on_arrival(6, _revive_every))
	assert_false(_arrive_dead(2).unit(0).alive, "room 2 is not a checkpoint")
	assert_true(_arrive_dead(3).unit(0).alive, "room 3 is")
	_restore_revive(was)

# ---------------------------------------------------------------------------
# the camp room, issue 803. Passing a FloorWalk replaces #802's arrival proxy
# with the real rule: the revive happens where the camp is and nowhere else.

func _walk_at(plan: FloorPlan, room_id: int) -> FloorWalk:
	var walk := FloorWalk.new(plan)
	walk.current_id = room_id
	return walk

func test_the_camp_revives_only_where_the_camp_is() -> void:
	var plan := FloorGenerator.generate(3)
	var party := _pair()
	var run := FloorRun.new()
	run.record_result(&"w", 0, 0, false)
	assert_false(FloorRun.should_revive(run, party, 5, _walk_at(plan, plan.entrance_id)),
		"one down anywhere else is not a camp")
	assert_true(FloorRun.should_revive(run, party, 5, _walk_at(plan, plan.camp_id)),
		"standing in the camp with anybody down spends it")

## The player: spent whether one pawn or four came back.
func test_the_camp_is_spent_on_use_and_survives_the_room_transition() -> void:
	var plan := FloorGenerator.generate(3)
	var party := _pair()
	var run := FloorRun.new()
	run.record_result(&"w", 0, 0, false)
	var walk := _walk_at(plan, plan.camp_id)
	var state := CombatSim.build(party, RoomLibrary.get_room(FloorGenerator.CAMP_ID), 1)
	FloorRun.carry_into(run, state, party, 5, walk)
	assert_true(state.unit(0).alive, "the one that was down comes back")
	assert_true(run.revive_used, "and the camp is spent")
	run.record_result(&"p", 0, 0, false)
	assert_false(FloorRun.should_revive(run, party, 6, _walk_at(plan, plan.camp_id)),
		"a spent camp is spent for the rest of the floor")

func test_an_intact_party_standing_in_the_camp_does_not_spend_it() -> void:
	var plan := FloorGenerator.generate(3)
	var party := _pair()
	var run := FloorRun.new()
	assert_false(FloorRun.should_revive(run, party, 5, _walk_at(plan, plan.camp_id)),
		"nobody is down, so there is nothing to spend it on")

## The camp is a place, not a chest.
func test_the_camp_drops_no_loot() -> void:
	var plan := FloorGenerator.generate(3)
	var party := _pair()
	var run := FloorRun.new()
	assert_eq(FloorRun.award_room_loot(run, plan.room(plan.camp_id), party, 3),
		[] as Array[EquipmentDef], "the camp fills no chest")
	assert_eq(run.loot.size(), 0)

## The detour rule, which the live floor and the headless sweep both read.
func test_the_party_turns_round_for_the_camp_only_when_all_three_hold() -> void:
	var plan := FloorGenerator.generate(3)
	var party := _pair()
	var run := FloorRun.new()
	var walk := FloorWalk.new(plan)
	assert_false(walk.wants_camp(run, party), "nobody is down")
	run.record_result(&"w", 0, 0, false)
	assert_false(walk.wants_camp(run, party), "one down is not #797's cliff")
	run.record_result(&"p", 0, 0, false)
	var host: int = plan.neighbours_of(plan.camp_id)[0]
	assert_eq(walk.wants_camp(run, party), walk.camp_found(),
		"two down is not enough on its own: the camp has to have been found")
	for id in walk._shortest_path(func(id: int) -> bool: return id == host):
		walk.enter(id)
	assert_true(walk.wants_camp(run, party), "found, needed and unspent")
	run.revive_used = true
	assert_false(walk.wants_camp(run, party), "a spent camp is not walked back to")
