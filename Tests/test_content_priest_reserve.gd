extends "res://Tests/TestCase.gd"


## Issue 138. The Priest's heal was not being out-prioritised, it was being
## **out-spent**: on `main`, across 192 real fights, an ally sat at or below the
## heal threshold and inside Heal's reach on 2,132 Priest-ticks, and the Priest
## could pay for the heal on 119 of them. The other 2,013 were Mana, none were
## cooldown. Priority decides who gets a tick; it decides nothing about who gets
## the Mana, and the three plans *below* the heal had already spent it.

const HEAL_ID := &"priest_heal"
const HEAL_PLAN := &"priest_heal_hurt_ally"

## The plans below the heal, and the one thing they have in common is that each
## spends the same pool the heal spends.
const SPENDER_PLANS := {
	&"priest_ward_default": &"priest_ward",
	&"priest_haste_default": &"priest_haste",
	&"priest_smite_nearest": &"priest_smite",
}

# ---------------------------------------------------------------------------
# the reserve is the right number
# ---------------------------------------------------------------------------

## Derived from the registry rather than retyped: two independent artifacts,
## which is the only version of this check that can fail.
func test_the_reserve_covers_the_heal_plus_the_spender() -> void:
	var heal_cost: int = ActionLibrary.get_action(HEAL_ID).resource_cost
	assert_true(heal_cost > 0, "a free heal would make this whole issue moot")
	for plan_id in SPENDER_PLANS:
		var action_id: StringName = SPENDER_PLANS[plan_id]
		var cost: int = ActionLibrary.get_action(action_id).resource_cost
		assert_true(PresetPlans.PRIEST_SPENDER_RESERVE >= heal_cost + cost,
			"%s costs %d and priest_heal costs %d, so a Priest may cast it only from %d Mana or more, not %d" % [
				action_id, cost, heal_cost, heal_cost + cost, PresetPlans.PRIEST_SPENDER_RESERVE
			])

## The heal must stay above the reserved plans, or the reserve is protecting
## nothing: a plan that never gets a tick does not need the Mana kept for it.
func test_the_heal_is_still_first_and_every_plan_under_it_reserves() -> void:
	var plans := PresetPlans.for_class(&"priest")
	assert_true(plans.size() > 0, "the Priest ships preset plans")
	assert_eq(plans[0].id, HEAL_PLAN, "the heal is the first plan the Priest consults")
	var seen := 0
	for i in range(1, plans.size()):
		var plan = plans[i]
		var action_id := _action_of(plan)
		if action_id == &"" or ActionLibrary.get_action(action_id) == null:
			continue
		if ActionLibrary.get_action(action_id).resource_cost <= 0:
			continue
		seen += 1
		assert_true(plan.condition is SelfResourceAtLeastBlock,
			"%s sits under the heal and spends the heal's Mana, so its condition must state a reserve" % plan.id)
		var reserve := (plan.condition as SelfResourceAtLeastBlock).amount
		assert_true(reserve >= PresetPlans.PRIEST_SPENDER_RESERVE,
			"%s reserves %s, less than PRIEST_SPENDER_RESERVE" % [plan.id, reserve])
	assert_eq(seen, SPENDER_PLANS.size(),
		"a Mana-spending plan was added or removed under the heal without this file being told")

# ---------------------------------------------------------------------------
# and the fight obeys it
# ---------------------------------------------------------------------------

## Runs real fights and watches what a Priest commits to. **A structural check
## cannot replace this**: `PlanInterpreter` could stop reading conditions, or a
## fall-through could route a lower spender through `DefaultBehavior` instead,
## and every assertion above would still pass.
func test_no_priest_ever_spends_below_the_reserve_in_a_real_fight() -> void:
	var spender_actions := {}
	for plan_id in SPENDER_PLANS:
		spender_actions[SPENDER_PLANS[plan_id]] = true

	var violations := 0
	var starts := 0
	var fights := 0
	for encounter_id in [&"floor1_room1", &"floor1_horde", &"floor1_ghoul_den"]:
		if RoomLibrary.get_room(encounter_id) == null:
			continue
		for fight_seed in 4:
			fights += 1
			var party: Array[PawnData] = []
			for cid in [&"priest", &"warrior", &"abomination", &"geysermancer"]:
				party.append(PawnFactory.make_preset_pawn(cid, StringName("p%d" % party.size()), String(cid)))
			var deps := SimDeps.new()
			var state := CombatSim.build(party, RoomLibrary.get_room(encounter_id), fight_seed, deps)
			var mana_before := {}
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				for u in state.units:
					if u.alive and u.actions.has(HEAL_ID):
						mana_before[[state.tick + 1, u.id]] = u.resource
				CombatSim.step(state, deps)
			for e in state.events:
				if e.kind != CG.EventKind.ACTION_START:
					continue
				if not spender_actions.has(e.action_id):
					continue
				var key := [e.tick, e.source_id]
				if not mana_before.has(key):
					continue
				starts += 1
				if int(mana_before[key]) < PresetPlans.PRIEST_SPENDER_RESERVE:
					violations += 1
	assert_true(fights > 0, "no encounter to run this against")
	assert_true(starts > 0,
		"no Priest cast Ward, Haste or Smite in %d fights -- this check saw nothing and proved nothing" % fights)
	assert_eq(violations, 0,
		"%d of %d spender casts started below the %d-Mana reserve" % [
			violations, starts, PresetPlans.PRIEST_SPENDER_RESERVE
		])

func _action_of(plan) -> StringName:
	for b in plan.blocks:
		if b is UseActionBlock:
			var a: ActionDef = (b as UseActionBlock).action
			return a.id if a != null else &""
	return &""
