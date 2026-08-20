extends "res://Tests/TestCase.gd"


## Issue 219. `SUSTAIN_START` and `SUSTAIN_END` were the last event kinds in the
## game that rendered a correct log line and **never happened** -- swift built
## the channel in #61 and left every action's `sustain_cost_per_tick` at 0 on
## purpose, so the mechanism shipped, passed its own suite, satisfied #151's
## exhaustiveness guard, and fired zero times in 100 fights.
##
## `abomination_immolate` is the content that makes them happen, and this file is
## what stops it going quietly back to zero. **The load-bearing test is the
## behavioural one: it runs real fights, through the real registry and the real
## preset plans, and counts the two events.** A structural check on the
## `ActionDef` would pass on a build where nothing ever chose the action, which
## is the exact failure #219 exists to end -- and it is the failure this project
## has now shipped fourteen times.
##
## The negative half is here too, because a detector that only ever fires is not
## a detector: with the one plan removed the count must be **zero**, which also
## proves `DefaultBehavior` cannot reach a sustained action on its own.

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
## Recomputed here from the registry rather than retyped, so repricing Grapple
## and leaving the aura behind is red instead of silent. Two artifacts, which is
## the only version of this check that can fail.
func test_a_tick_of_the_channel_is_worth_a_tick_of_grapple() -> void:
	var grapple := Registry.get_action(GRAPPLE)
	var immolate := Registry.get_action(IMMOLATE)
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
	var grapple := Registry.get_action(GRAPPLE)
	var immolate := Registry.get_action(IMMOLATE)
	assert_true(
		immolate.sustain_radius > grapple.range_units,
		"aura radius %.1f should exceed grapple's %.1f" % [immolate.sustain_radius, grapple.range_units]
	)
	var plan: Plan = _immolate_plan()
	assert_not_null(plan, "the Abomination should ship %s" % IMMOLATE_PLAN)
	assert_almost_eq(
		float(plan.condition.args.get("range", -1.0)), immolate.sustain_radius, 0.0001,
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

func test_real_fights_ignite_and_end_the_channel() -> void:
	var r := _run(true)
	print("immolate over %d fights: %d ignitions, %d endings, %d ticks held, %d burn damage" % [
		SEEDS, r["starts"], r["ends"], r["held"], r["damage"]])
	# Not `> 0`: announcement rule 4 says an `> 0` on an emergent count reads the
	# same at twenty and at one and can only fail once it is already too late.
	# 3.08 a fight was measured over 120 seeds with `Tools/ImmolateWindow.gd`;
	# the floor is a third of that, so a real slide is red while the mechanism is
	# still alive.
	assert_true(r["starts"] >= SEEDS, "the channel should ignite about three times a fight, got %d in %d" % [r["starts"], SEEDS])
	# **Not `ends == starts`, and the gap is a finding rather than a tolerance.**
	# A fight stops the tick its outcome resolves, so a channel still burning at
	# that moment never reaches `_end_sustain` and emits no SUSTAIN_END -- the
	# log's last word on it is "Immolate begins". At most one per fight, and this
	# asserts exactly that count against the units actually left holding one, so
	# a second cause of a missing end is red. Reported to swift and rook rather
	# than worked around: it is `CombatSim`'s file, not mine.
	assert_eq(r["ends"], r["starts"] - r["open_at_end"], "every channel ends except one still burning when the fight stops")
	assert_true(r["held"] >= r["starts"], "a channel should last at least a tick, held %d over %d channels" % [r["held"], r["starts"]])
	assert_true(r["damage"] > 0, "and the burn should reach somebody")

## The negative half, fed known-good input. Removing the one plan must take the
## count to exactly zero -- which is also the live proof that `DefaultBehavior`
## cannot light a channel, because `abomination_immolate` is still in the
## Abomination's action list in this arm.
func test_without_its_plan_nothing_in_the_game_holds_a_channel() -> void:
	var r := _run(false)
	assert_eq(r["starts"], 0, "no channel should ignite without the plan")
	assert_eq(r["ends"], 0, "and none should end")
	assert_eq(r["damage"], 0, "and no aura damage should land")
	assert_eq(r["open_at_end"], 0, "and nobody is left holding one")

# ---------------------------------------------------------------------------

func _immolate_plan() -> Plan:
	for p in PresetPlans.for_class(&"abomination"):
		if p.id == IMMOLATE_PLAN:
			return p
	return null

func _run(with_plan: bool) -> Dictionary:
	var starts := 0
	var ends := 0
	var held := 0
	var damage := 0
	var open_at_end := 0
	for s in SEEDS:
		var party: Array[PawnData] = []
		for cid in PARTY:
			var pawn := PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid))
			if not with_plan:
				var kept: Array = []
				for p in pawn.plans:
					if p.id != IMMOLATE_PLAN:
						kept.append(p)
				pawn.plans.assign(kept)
			party.append(pawn)
		var state := CombatSim.build(party, Registry.get_encounter(ENCOUNTER), s)
		CombatSim.run(state)
		for u in state.units:
			if u.sustaining != &"":
				open_at_end += 1
		for e in state.events:
			match e.kind:
				CG.EventKind.SUSTAIN_START:
					starts += 1
				CG.EventKind.SUSTAIN_END:
					ends += 1
					held += e.amount
				CG.EventKind.DAMAGE:
					if e.action_id == IMMOLATE:
						damage += e.amount
	return {"starts": starts, "ends": ends, "held": held, "damage": damage, "open_at_end": open_at_end}
