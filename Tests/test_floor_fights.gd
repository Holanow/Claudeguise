extends "res://Tests/TestCase.gd"


## Covers all four acceptance criteria in Issues/issue-9-rooms-run-fights.md.

## Issue 12: swapped Siege Master -> Abomination. This file tests the floor/
## room seam, not any one class's balance, so the fixture does not need to be
## siege_master specifically -- and on this branch it currently cannot win a
## boss room reliably (build_siege_engine's summon does nothing until wren's
## mid-fight unit spawning lands), which was failing tests below that have
## nothing to do with the Siege Master's own rebuild.
func _make_party() -> Array[PawnData]:
	return [
		PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior"),
		PawnFactory.make_starter_pawn(&"priest", &"priest", "Priest"),
		PawnFactory.make_starter_pawn(&"geysermancer", &"geysermancer", "Geysermancer"),
		PawnFactory.make_starter_pawn(&"abomination", &"abomination", "Abomination"),
	]

func _single_room_plan(seed: int, difficulty: int) -> FloorPlan:
	var plan := FloorPlan.new()
	plan.seed = seed
	var r := FloorRoom.new()
	r.id = 0
	r.type = FloorRoom.Type.ENEMY
	r.difficulty = difficulty
	plan.rooms = [r]
	plan.entrance_id = 0
	plan.miniboss_id = -1
	plan.boss_id = -1
	return plan

# ---------------------------------------------------------------------------
# criterion 1: a room's outcome carries forward
# ---------------------------------------------------------------------------

func test_carried_condition_overrides_a_freshly_built_units_stats() -> void:
	var party := _make_party()
	var plan := _single_room_plan(55, 1)
	var run := FloorRun.new(plan)
	run.record_result(party[0].id, 5, 1, true)
	run.record_result(party[1].id, 0, 0, false)

	var encounter := Registry.get_encounter(&"floor1_room1")
	var state := CombatSim.build(party, encounter, 999)
	FloorFightRunner._carry_party_condition_into(state, run, party)

	assert_eq(state.unit(0).hp, 5, "reduced hp must override a freshly built unit's full hp")
	assert_eq(state.unit(0).resource, 1, "reduced resource must carry the same way")
	assert_true(state.unit(0).alive)

	assert_false(state.unit(1).alive, "a pawn recorded dead must build in dead")
	assert_eq(state.unit(1).hp, 0)

	# An untouched pawn (never recorded) defaults to full, matching FloorRun's
	# own contract from issue 5 -- a pawn that has not fought yet is fresh.
	assert_eq(state.unit(2).hp, state.unit(2).hp_max, "an untouched pawn enters at full hp")
	assert_true(state.unit(2).alive)

func test_play_room_writes_the_result_back_into_floor_run() -> void:
	var party := _make_party()
	var plan := _single_room_plan(77, 4)
	var run := FloorRun.new(plan)

	FloorFightRunner.play_room(run, plan.room(0), party)

	for p in party:
		# Every pawn that fought has an entry now, whatever it says --
		# this is the mechanism, not a claim about who won.
		assert_true(run.carry.has(p.id), "%s must have a recorded result after fighting" % p.display_name)

# ---------------------------------------------------------------------------
# criterion 2: a wipe ends the run; winning the last room ends it the other way
# ---------------------------------------------------------------------------

func test_a_wipe_ends_the_run_in_defeat() -> void:
	var party := _make_party()
	var plan := _single_room_plan(12, 1)
	var run := FloorRun.new(plan)
	for p in party:
		run.record_result(p.id, 0, 0, false) # the party arrives already wiped

	var result := FloorFightRunner.play_room(run, plan.room(0), party)

	assert_eq(result.outcome, FloorFightRunner.Outcome.DEFEAT)
	for p in party:
		assert_false(run.is_alive(p.id), "a wiped party must still be wiped after the room resolves")

func test_outcome_mapping_covers_defeat_continue_and_victory() -> void:
	assert_eq(
		FloorFightRunner._map_outcome(CombatState.Outcome.PLAYER_WIN, false),
		FloorFightRunner.Outcome.CONTINUES,
		"a non-boss room win continues the run"
	)
	assert_eq(
		FloorFightRunner._map_outcome(CombatState.Outcome.PLAYER_WIN, true),
		FloorFightRunner.Outcome.VICTORY,
		"winning the boss room ends the run in victory"
	)
	assert_eq(
		FloorFightRunner._map_outcome(CombatState.Outcome.ENEMY_WIN, true),
		FloorFightRunner.Outcome.DEFEAT,
		"losing the boss room is still a defeat, not a victory"
	)
	assert_eq(
		FloorFightRunner._map_outcome(CombatState.Outcome.DRAW, false),
		FloorFightRunner.Outcome.DEFEAT,
		"a draw ends the run rather than continuing it"
	)

# ---------------------------------------------------------------------------
# criterion 3: the same seed plays the same floor the same way
# ---------------------------------------------------------------------------

func _play_all_fight_rooms(plan: FloorPlan) -> Array:
	var run := FloorRun.new(plan)
	var trace: Array = []
	for r in plan.rooms:
		if not FloorFightRunner.is_fight_room(r.type):
			continue
		var outcome: FloorFightRunner.Outcome = FloorFightRunner.play_room(run, r, _make_party()).outcome
		trace.append({"room": r.id, "outcome": outcome})
		if outcome != FloorFightRunner.Outcome.CONTINUES:
			break
	return trace

func test_same_seed_plays_the_same_floor_the_same_way() -> void:
	var plan_a := FloorGenerator.generate(300)
	var plan_b := FloorGenerator.generate(300)

	var trace_a := _play_all_fight_rooms(plan_a)
	var trace_b := _play_all_fight_rooms(plan_b)

	assert_eq(trace_a, trace_b, "the same floor seed must play the same rooms in the same order with the same outcomes")

func test_different_seeds_currently_agree_pending_issue_7_damage_variance() -> void:
	# Honest reporting per issue 9's own instruction: "if it still holds
	# trivially, say so rather than asserting a sameness that is really an
	# absence." Different floor seeds produce different room GRAPHS (issue
	# 5's own determinism test covers that) but whether the FIGHTS diverge
	# depends on issue 7 landing damage variance from state.rng. Today
	# nothing reads it for combat outcomes, so two different seeds still
	# play the identical miniboss fight -- the miniboss room is guaranteed
	# fight-typed and same-difficulty in every generated plan, so it's the
	# one room id safe to compare across arbitrary seeds.
	var plan_a := FloorGenerator.generate(1)
	var plan_b := FloorGenerator.generate(2)
	var run_a := FloorRun.new(plan_a)
	var run_b := FloorRun.new(plan_b)

	var outcome_a: FloorFightRunner.Outcome = FloorFightRunner.play_room(run_a, plan_a.room(plan_a.miniboss_id), _make_party()).outcome
	var outcome_b: FloorFightRunner.Outcome = FloorFightRunner.play_room(run_b, plan_b.room(plan_b.miniboss_id), _make_party()).outcome

	assert_eq(
		outcome_a, outcome_b,
		"expected today, not the ideal: without issue 7's damage variance, different seeds still agree"
	)

# ---------------------------------------------------------------------------
# criterion 4: difficulty means something
# ---------------------------------------------------------------------------

## FINDING, not just a test: with today's single authored encounter and the
## balanced party (the same composition SampleFights already measured at
## 20/20 with all four survivors), scaling the *count* of that encounter's
## enemies from 1 to 4 produces zero measurable difference. See the printed
## distribution and the comment below the assertions -- this is the same
## landslide-balance problem issue 7 is addressing, not a defect in the
## wiring here. Per issue 9's own "what would make stopping the right
## answer": reporting this rather than asserting a curve that is not real.
func test_difficulty_makes_rooms_measurably_harder_and_room_one_is_winnable() -> void:
	var avg_survivors_by_difficulty: Dictionary = {}
	for difficulty in [1, 2, 3, 4]:
		var total_survivors := 0
		for seed in range(1, 21):
			var party := _make_party()
			var plan := _single_room_plan(seed, difficulty)
			var run := FloorRun.new(plan)
			FloorFightRunner.play_room(run, plan.room(0), party)
			for p in party:
				if run.is_alive(p.id):
					total_survivors += 1
		avg_survivors_by_difficulty[difficulty] = float(total_survivors) / 20.0

	print("average survivors out of 4, by difficulty, 20 seeds each, balanced party: ", avg_survivors_by_difficulty)

	# Holds today, and is the half of criterion 4 this test can honestly
	# assert: the first room (difficulty 1) is winnable by a starting party
	# in the large majority of seeds.
	assert_true(
		float(avg_survivors_by_difficulty[1]) >= 3.5,
		"difficulty 1 (the first room's difficulty) must be winnable by a starting party in the large majority of seeds: %s" % [avg_survivors_by_difficulty]
	)

	# Does NOT hold today, and is reported rather than asserted: with only
	# one authored encounter, scaling its enemy count 1x to 4x does not
	# produce a measurable survivor difference for this party (4.0/4.0 at
	# every difficulty in the run that produced the numbers in this file's
	# board post). Room-count scaling is a real difficulty lever in
	# principle, but it cannot show up while the strongest tested party
	# beats the full room cleanly regardless -- more/harder content, or
	# issue 7's tuning pass, is what would make this measurable, and
	# neither is this issue's to build. Not asserting a fabricated gap here.

# ---------------------------------------------------------------------------
# first floor phase: MINIBOSS and BOSS are distinct rooms
# ---------------------------------------------------------------------------

## Before this: both room types resolved to the same encounter id, so a
## "boss room" and a "miniboss room" were the identical fight with a
## different label. This only checks the id, not any particular content --
## which ids they are is a call for whoever authors real boss content
## later, not fixed here.
func test_miniboss_and_boss_rooms_are_different_encounters() -> void:
	var miniboss_room := FloorRoom.new()
	miniboss_room.id = 0
	miniboss_room.type = FloorRoom.Type.MINIBOSS
	miniboss_room.difficulty = 5

	var boss_room := FloorRoom.new()
	boss_room.id = 1
	boss_room.type = FloorRoom.Type.BOSS
	boss_room.difficulty = 10

	var miniboss_encounter := FloorFightRunner._encounter_for(miniboss_room)
	var boss_encounter := FloorFightRunner._encounter_for(boss_room)

	assert_ne(
		miniboss_encounter.id, boss_encounter.id,
		"a miniboss room and a boss room must not be the same fight"
	)

# ---------------------------------------------------------------------------
# issue 42's call site: rooms that win can drop loot
# ---------------------------------------------------------------------------

func _single_room_plan_of_type(seed: int, room_type: FloorRoom.Type, difficulty: int) -> FloorPlan:
	var plan := FloorPlan.new()
	plan.seed = seed
	var r := FloorRoom.new()
	r.id = 0
	r.type = room_type
	r.difficulty = difficulty
	plan.rooms = [r]
	plan.entrance_id = 0
	plan.miniboss_id = -1
	plan.boss_id = -1
	return plan

## BOSS always drops per LootTables.DROP_CHANCE -- a deterministic case to
## assert against rather than depending on a lucky roll.
func test_a_won_boss_room_can_drop_loot() -> void:
	var party := _make_party()
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.BOSS, 10)
	var run := FloorRun.new(plan)

	FloorFightRunner.play_room(run, plan.room(0), party)

	assert_eq(run.loot.size(), 1, "a boss room (100% drop chance) that resolves must drop exactly one item")

## ENEMY has 0% drop chance in LootTables -- confirms the wiring does not
## force a drop where the table says there should not be one.
func test_a_won_ordinary_enemy_room_never_drops() -> void:
	var party := _make_party()
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.ENEMY, 1)
	var run := FloorRun.new(plan)

	FloorFightRunner.play_room(run, plan.room(0), party)

	assert_eq(run.loot.size(), 0, "an ordinary enemy room must never drop, per LootTables' own table")

## A wiped party does not loot the room that wiped it.
func test_a_lost_fight_never_drops_loot() -> void:
	var party := _make_party()
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.BOSS, 10)
	var run := FloorRun.new(plan)
	for p in party:
		run.record_result(p.id, 0, 0, false) # arrives already wiped

	FloorFightRunner.play_room(run, plan.room(0), party)

	assert_eq(run.loot.size(), 0, "a party that cannot win must not loot the room")

func test_same_floor_seed_drops_the_same_loot() -> void:
	var plan_a := _single_room_plan_of_type(42, FloorRoom.Type.BOSS, 10)
	var plan_b := _single_room_plan_of_type(42, FloorRoom.Type.BOSS, 10)
	var run_a := FloorRun.new(plan_a)
	var run_b := FloorRun.new(plan_b)

	FloorFightRunner.play_room(run_a, plan_a.room(0), _make_party())
	FloorFightRunner.play_room(run_b, plan_b.room(0), _make_party())

	assert_eq(run_a.loot.size(), run_b.loot.size(), "same floor seed must drop the same number of items")
	if run_a.loot.size() > 0:
		assert_eq(run_a.loot[0].id, run_b.loot[0].id, "same floor seed must drop the same item")

## TREASURE is not a fight room -- play_treasure_room is its own entry
## point, and it always drops (100% per LootTables).
func test_a_treasure_room_always_drops() -> void:
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.TREASURE, 1)
	var run := FloorRun.new(plan)

	FloorFightRunner.play_treasure_room(run, plan.room(0))

	assert_eq(run.loot.size(), 1, "a treasure room (100% drop chance) must always drop")
	assert_true(run.visited.has(0), "visiting a treasure room must mark it visited, same as a fight room")

# ---------------------------------------------------------------------------
# issue 45's call site: recovery and revival between rooms
# ---------------------------------------------------------------------------

## _apply_between_room_recovery tested directly, same pattern as
## _map_outcome and _encounter_for above -- the fight itself is
## non-deterministic in exactly which hp a party ends on, so hand-setting
## the carried state before recovery is the only way to assert an exact
## fraction rather than a real fight's incidental numbers.
func test_a_living_pawn_recovers_a_fraction_of_missing_hp_with_a_healer() -> void:
	var party := _make_party() # includes a Priest -- a living healer
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.ENEMY, 1)
	var run := FloorRun.new(plan)

	var warrior := party[0]
	var hp_max := Balance.max_hp(warrior)
	var half := hp_max / 2
	run.record_result(warrior.id, half, 0, true)

	FloorFightRunner._apply_between_room_recovery(run, party)

	var expected := Balance.between_room_heal(half, hp_max, true)
	assert_eq(run.hp_for(warrior.id, hp_max), expected, "a living pawn must recover exactly Balance's own fraction with a healer present")
	assert_true(run.hp_for(warrior.id, hp_max) > half, "recovery must be a real improvement, not a no-op")

## The gap swift's floor investigation found: hp recovered between rooms and
## resource never did, so a party could read as "85% healthy" while its
## casters sat on single-digit mana. Balance.between_room_resource_recover
## exists and is wired here the same way the hp path already was.
func test_a_living_pawn_recovers_a_fraction_of_missing_resource_too() -> void:
	var party := _make_party()
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.ENEMY, 1)
	var run := FloorRun.new(plan)

	var priest := party[1]
	var resource_max := Balance.max_resource(priest)
	var near_empty := 2
	run.record_result(priest.id, Balance.max_hp(priest), near_empty, true)

	FloorFightRunner._apply_between_room_recovery(run, party)

	var expected := Balance.between_room_resource_recover(near_empty, resource_max)
	assert_eq(run.resource_for(priest.id, resource_max), expected, "resource must recover exactly Balance's own fraction, mirroring the hp path")
	assert_true(run.resource_for(priest.id, resource_max) > near_empty, "resource recovery must be a real improvement, not a no-op -- this was the whole gap")

func test_a_dead_pawn_stays_dead_without_a_living_healer() -> void:
	var party: Array[PawnData] = [
		PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior"),
		PawnFactory.make_starter_pawn(&"geysermancer", &"geysermancer", "Geysermancer"),
		PawnFactory.make_starter_pawn(&"siege_master", &"siege_master", "Siege Master"),
		PawnFactory.make_starter_pawn(&"abomination", &"abomination", "Abomination"),
	] # no healer role anywhere in this party
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.ENEMY, 1)
	var run := FloorRun.new(plan)
	run.record_result(party[0].id, 0, 0, false) # the warrior died in the fight

	FloorFightRunner._apply_between_room_recovery(run, party)

	assert_false(run.is_alive(party[0].id), "a dead pawn must stay dead when nothing in the party can revive it")

func test_a_dead_pawn_revives_at_a_partial_fraction_with_a_living_healer() -> void:
	var party := _make_party() # includes a living Priest
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.ENEMY, 1)
	var run := FloorRun.new(plan)
	var warrior := party[0]
	run.record_result(warrior.id, 0, 0, false) # died in the fight

	FloorFightRunner._apply_between_room_recovery(run, party)

	assert_true(run.is_alive(warrior.id), "a dead pawn must revive with a living healer in the party")
	var hp_max := Balance.max_hp(warrior)
	assert_eq(run.hp_for(warrior.id, hp_max), Balance.revive_hp(hp_max, true), "must revive at exactly Balance's own fraction, not full health")
	assert_true(run.hp_for(warrior.id, hp_max) < hp_max, "a revival is a second chance, not a free win back")

func test_recovery_does_not_apply_after_a_defeat() -> void:
	var party := _make_party()
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.BOSS, 10)
	var run := FloorRun.new(plan)
	for p in party:
		run.record_result(p.id, 0, 0, false) # arrives already wiped

	FloorFightRunner.play_room(run, plan.room(0), party)

	for p in party:
		assert_false(run.is_alive(p.id), "a wipe must not trigger revival -- there is no next room to recover into")

# ---------------------------------------------------------------------------
# issue 5's second gap: CELL replaces a loss
# ---------------------------------------------------------------------------

func test_cell_candidates_excludes_classes_already_alive_in_the_party() -> void:
	var party := _make_party() # warrior, priest, geysermancer, abomination, all alive
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.CELL, 1)
	var run := FloorRun.new(plan)

	var candidates := FloorFightRunner.cell_candidates(run, plan.room(0), party)

	for c in candidates:
		for p in party:
			assert_ne(c.pawn_class.id, p.pawn_class.id, "must not offer a class already alive in the party")

func test_cell_candidates_offers_a_dead_pawns_own_class_again() -> void:
	var party := _make_party()
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.CELL, 1)
	var run := FloorRun.new(plan)
	run.record_result(party[0].id, 0, 0, false) # the warrior died

	var candidates := FloorFightRunner.cell_candidates(run, plan.room(0), party)

	var offers_warrior := false
	for c in candidates:
		if c.pawn_class.id == &"warrior":
			offers_warrior = true
	assert_true(offers_warrior, "a dead party member's class must be a fair candidate again -- replacing that slot is the point")

func test_same_floor_seed_offers_the_same_cell_candidates() -> void:
	var plan_a := _single_room_plan_of_type(88, FloorRoom.Type.CELL, 1)
	var plan_b := _single_room_plan_of_type(88, FloorRoom.Type.CELL, 1)
	var run_a := FloorRun.new(plan_a)
	var run_b := FloorRun.new(plan_b)

	var candidates_a := FloorFightRunner.cell_candidates(run_a, plan_a.room(0), _make_party())
	var candidates_b := FloorFightRunner.cell_candidates(run_b, plan_b.room(0), _make_party())

	assert_eq(candidates_a.size(), candidates_b.size(), "same floor seed must offer the same number of candidates")
	for i in candidates_a.size():
		assert_eq(candidates_a[i].pawn_class.id, candidates_b[i].pawn_class.id, "same floor seed must offer the same candidate %d" % i)

func test_resolve_cell_replaces_the_first_dead_party_member() -> void:
	var party := _make_party()
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.CELL, 1)
	var run := FloorRun.new(plan)
	run.record_result(party[1].id, 0, 0, false) # the priest died

	var candidates := FloorFightRunner.cell_candidates(run, plan.room(0), party)
	assert_true(candidates.size() > 0, "sanity: there must be a candidate to pick")
	var chosen := candidates[0]

	var replaced := FloorFightRunner.resolve_cell(run, plan.room(0), party, chosen)

	assert_true(replaced, "resolve_cell must report a real replacement")
	assert_eq(party[1].id, chosen.id, "the dead slot must now hold the chosen recruit")
	assert_true(run.is_alive(party[1].id), "a fresh recruit, never having fought, must read as alive")
	assert_true(run.visited.has(0), "resolving a CELL must mark it visited, same as any other room")

func test_resolve_cell_does_nothing_to_the_roster_when_nobody_is_dead() -> void:
	var party := _make_party()
	var original_ids: Array[StringName] = []
	for p in party:
		original_ids.append(p.id)
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.CELL, 1)
	var run := FloorRun.new(plan)

	var candidates := FloorFightRunner.cell_candidates(run, plan.room(0), party)
	var replaced := FloorFightRunner.resolve_cell(run, plan.room(0), party, candidates[0])

	assert_false(replaced, "resolve_cell must report no replacement when nobody is dead")
	for i in party.size():
		assert_eq(party[i].id, original_ids[i], "the roster must be unchanged when there is no dead slot to fill")
	assert_true(run.visited.has(0), "the room still resolves even when nothing changes")

func test_a_recruited_pawn_enters_the_next_room_at_full_health() -> void:
	var party := _make_party()
	var plan := _single_room_plan_of_type(1, FloorRoom.Type.CELL, 1)
	var run := FloorRun.new(plan)
	run.record_result(party[2].id, 0, 0, false) # the geysermancer died

	var candidates := FloorFightRunner.cell_candidates(run, plan.room(0), party)
	FloorFightRunner.resolve_cell(run, plan.room(0), party, candidates[0])

	var recruit := party[2]
	var recruit_hp_max := Balance.max_hp(recruit)
	assert_eq(run.hp_for(recruit.id, recruit_hp_max), recruit_hp_max, "a recruit's id must not collide with the dead pawn's carry entry")
