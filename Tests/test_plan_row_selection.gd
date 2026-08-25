extends "res://Tests/TestCase.gd"


## Issue 575: pins how a plan row is chosen, so a fix has to break these on
## purpose rather than by accident.

const SEEDS := 4

## The row `PlanInterpreter` would pick if this unit were free, or -1 for none.
## `state.tick` moves by one so cooldowns compare against the tick
## `_decide_phase` would use, and `focus_id` is restored: `decide` writes it.
func _row_that_would_win(state: CombatState, unit: CombatUnit) -> int:
	var saved := unit.focus_id
	state.tick += 1
	var won := -1
	for i in PlanInterpreter.active_plan_count(unit.pawn):
		var plan: Plan = unit.pawn.plans[i]
		if PlanInterpreter.condition_holds(state, unit, plan) \
			and PlanInterpreter._run_blocks(state, unit, plan) != null:
			won = i
			break
	state.tick -= 1
	unit.focus_id = saved
	return won

## Named by class id, never by position in the roster: `all_class_ids()` sorts
## the Warrior fifth of five and slicing it drops him. Issue 350.
const PARTY := [&"warrior", &"priest", &"geysermancer", &"siege_master"]

func _preset_party() -> Array[PawnData]:
	var party: Array[PawnData] = []
	for cid in PARTY:
		party.append(PawnFactory.make_preset_pawn(cid, StringName("%s_p" % cid), String(cid)))
	return party

# ---------------------------------------------------------------------------

## `SampleFights` and almost every tool build starter pawns, so what they
## measure is `DefaultBehavior` and not the plan layer.
func test_a_starter_pawn_carries_no_plans_at_all() -> void:
	for cid in Registry.all_class_ids():
		var starter := PawnFactory.make_starter_pawn(cid, &"s", "s")
		assert_eq(starter.plans.size(), 0, "%s starter pawn should carry no plans" % cid)
		var preset := PawnFactory.make_preset_pawn(cid, &"p", "p")
		assert_true(preset.plans.size() > 0, "%s preset pawn should carry its library" % cid)

## The second, silent way a row loses, and it is not the condition. The
## Abomination's top row wants the nearest un-poisoned enemy and its claw
## reaches 45 units; nothing spawns within 400 of a pawn in any encounter.
func test_a_row_whose_condition_holds_still_loses_when_the_action_cannot_fire() -> void:
	var party: Array[PawnData] = [PawnFactory.make_preset_pawn(&"abomination", &"a", "a")]
	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 0)
	var unit := state.units[0]
	state.tick += 1
	var top: Plan = unit.pawn.plans[0]
	assert_true(PlanInterpreter.condition_holds(state, unit, top),
		"the Abomination's top row's condition holds at the first instant")
	assert_eq(PlanInterpreter._run_blocks(state, unit, top), null,
		"and the row still produces no intent, because the claw cannot reach")

## Nothing spawns inside the shortest proximity condition any preset row uses,
## so a proximity-gated row can never win the first instant of a fight.
func test_no_encounter_spawns_a_pawn_within_400_units_of_an_enemy() -> void:
	for eid in Registry.all_encounter_ids():
		var state := CombatSim.build(_preset_party(), Registry.get_encounter(eid), 0)
		for unit in state.units:
			if unit.pawn == null:
				continue
			for foe in state.living(CG.Team.ENEMY):
				assert_true(unit.position.distance_to(foe.position) > 400.0,
					"%s: a pawn spawns %.0f units from an enemy" % [
						eid, unit.position.distance_to(foe.position)])

## Order is priority among the rows that can act, and `decide` picks exactly the
## first of them. The two implementations must not drift.
func test_decide_returns_the_first_row_that_produces_an_intent() -> void:
	var state := CombatSim.build(_preset_party(), Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 0)
	var checked := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < 400:
		for unit in state.units:
			if not unit.alive or unit.pawn == null or unit.is_busy():
				continue
			var want := _row_that_would_win(state, unit)
			var saved := unit.focus_id
			state.tick += 1
			var intent := PlanInterpreter.decide(state, unit)
			state.tick -= 1
			unit.focus_id = saved
			checked += 1
			if want == -1:
				assert_eq(intent, null, "no row can act, so decide returns null")
			else:
				assert_eq(intent.source_plan, unit.pawn.plans[want].id,
					"decide should take row %d" % want)
		CombatSim.step(state)
	assert_true(checked > 100, "the walk should have inspected real free ticks")

## The corollary, and it is deliberate: a busy pawn's plan is not read, so a row
## that becomes ready mid-action waits. Measured at 9.5% of busy ticks across
## the whole game; this pins that the population is not zero.
func test_a_busy_pawn_does_not_read_a_row_that_became_ready() -> void:
	var blocked := 0
	var longest := 0
	for s in SEEDS:
		var state := CombatSim.build(_preset_party(), Registry.get_encounter(CG.DEFAULT_ENCOUNTER), s)
		var committed := {}
		var running := {}
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			for unit in state.units:
				if not unit.alive or unit.pawn == null:
					continue
				if unit.has_status(CG.Status.STUN) or unit.has_status(CG.Status.TAUNTED):
					continue
				var want := _row_that_would_win(state, unit)
				if not unit.is_busy():
					committed[unit.id] = want if want != -1 else 9999
					running[unit.id] = 0
					continue
				if want != -1 and want < int(committed.get(unit.id, 9999)):
					blocked += 1
					running[unit.id] = int(running.get(unit.id, 0)) + 1
					longest = maxi(longest, int(running[unit.id]))
				else:
					running[unit.id] = 0
			CombatSim.step(state)
	assert_true(blocked > 0,
		"a higher row should become ready mid-action somewhere in %d fights" % SEEDS)
	assert_true(longest > 1,
		"and it should go unread for more than a single tick, not just the one it arrived on")

## Asking the question must not change the answer, which is what makes every
## number above a measurement.
func test_asking_which_row_would_win_does_not_perturb_the_fight() -> void:
	for s in SEEDS:
		assert_eq(_fight(s, true), _fight(s, false), "seed %d perturbed by probing" % s)

func _fight(seed_value: int, probed: bool) -> String:
	var state := CombatSim.build(_preset_party(), Registry.get_encounter(CG.DEFAULT_ENCOUNTER), seed_value)
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		if probed:
			for unit in state.units:
				if unit.alive and unit.pawn != null:
					_row_that_would_win(state, unit)
		CombatSim.step(state)
	var hp := 0
	for u in state.units:
		hp += maxi(0, u.hp)
	return "tick %d outcome %d hp %d" % [state.tick, state.outcome, hp]
