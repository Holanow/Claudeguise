extends "res://Tests/TestCase.gd"


## Issue 219. `SUSTAIN_START` and `SUSTAIN_END` were the last event kinds in the
## game that rendered a correct log line and **never happened** -- swift built
## the channel in #61 and left every action's `sustain_cost_per_tick` at 0 on
## purpose, so the mechanism shipped, passed its own suite, satisfied #151's
## exhaustiveness guard, and fired zero times in 100 fights.

const IMMOLATE := &"abomination_immolate"
const IMMOLATE_PLAN := &"abomination_immolate_dump"
const GRAPPLE := &"abomination_grapple"
const ENCOUNTER := &"floor1_room1"
const PARTY := [&"abomination", &"geysermancer", &"priest", &"warrior"]
const SEEDS := 8

# ---------------------------------------------------------------------------
# the numbers are the derivation, not a taste
# ---------------------------------------------------------------------------

## `IMMOLATE_TICK_POWER_SCALE` is Grapple's own power over Grapple's own cycle.
func test_a_tick_of_the_channel_is_worth_a_tick_of_grapple() -> void:
	var grapple := ActionLibrary.get_action(GRAPPLE)
	var immolate := ActionLibrary.get_action(IMMOLATE)
	assert_not_null(grapple, "grapple should exist")
	assert_not_null(immolate, "immolate should exist")
	var cycle := grapple.wind_up_ticks + grapple.recover_ticks
	assert_true(cycle > 0, "a cycle of zero ticks would make the derivation meaningless")
	assert_almost_eq(
		immolate.power_scale, grapple.power_scale / float(cycle), 0.0001,
		"a tick of the aura should be worth a tick of Grapple"
	)

## The band the plan is named for: close enough to burn, too far to grip. If the
## aura ever reached no further than Grapple it would have no window of its own
## and would only ever fire on ticks Grapple declined for some other reason.
func test_the_aura_reaches_further_than_the_grip() -> void:
	var grapple := ActionLibrary.get_action(GRAPPLE)
	var immolate := ActionLibrary.get_action(IMMOLATE)
	assert_true(
		immolate.sustain_radius > grapple.range_units,
		"aura radius %.1f should exceed grapple's %.1f" % [immolate.sustain_radius, grapple.range_units]
	)
	var plan: Plan = _immolate_plan()
	assert_not_null(plan, "the Abomination should ship %s" % IMMOLATE_PLAN)
	assert_almost_eq(
		(plan.condition as EnemyInRangeBlock).range_units, immolate.sustain_radius, 0.0001,
		"the plan should hold the channel over exactly the ground the channel reaches"
	)

## Its position in the ladder, asserted because the position is the design and it
## was chosen by measurement: first the channel starved Grapple to 0.13 casts a
## fight, last it fired 0.17 times a fight. Third is the arrangement where all
## four actions stay alive. Moving it is allowed and should be deliberate.
func test_the_channel_sits_between_the_grip_and_the_hook() -> void:
	var ids: Array[StringName] = []
	for p in PresetPlans.for_class(&"abomination"):
		ids.append(p.id)
	assert_eq(
		ids,
		[&"abomination_claw_the_unpoisoned", &"abomination_grapple_close", IMMOLATE_PLAN, &"abomination_hook_far"] as Array[StringName],
		"the Abomination's plan order"
	)

# ---------------------------------------------------------------------------
# it actually happens, and only because of the plan
# ---------------------------------------------------------------------------
func _immolate_plan() -> Plan:
	for p in PresetPlans.for_class(&"abomination"):
		if p.id == IMMOLATE_PLAN:
			return p
	return null