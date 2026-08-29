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

## Issue 772. Immolate no longer leans on an attack stat at all -- it burns
## off the Abomination's own max hp, the same shape BURN and POISON already
## use (`Balance.status_damage_per_tick`). `power_scale` is retired to 0 so
## the two sources can never both be live on the same hit by accident.
func test_the_channel_deals_no_power_scale_damage() -> void:
	var immolate := ActionLibrary.get_action(IMMOLATE)
	assert_not_null(immolate, "immolate should exist")
	assert_eq(immolate.power_scale, 0.0, "power_scale is retired for this action")

## 3% of the Abomination's own max hp per second, divided across the 15 ticks
## the sustain fires on: 3.0 / 15 = 0.2% per tick. Worked from the rate rather
## than the other way around, so the two numbers cannot silently disagree.
func test_the_channel_deals_three_percent_of_the_abominations_max_hp_per_second() -> void:
	var immolate := ActionLibrary.get_action(IMMOLATE)
	var hit := immolate.hit()
	assert_not_null(hit, "immolate should carry a HitEffect")
	assert_almost_eq(
		hit.caster_max_hp_percent * float(CG.TICKS_PER_SECOND), 3.0, 0.0001,
		"one tick's percent, times the ticks in a second, should be the per-second rate"
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

# ---------------------------------------------------------------------------
# issue 772: a plan row is how a player stops the aura
# ---------------------------------------------------------------------------

## `self_hp_below_fraction` already exists in `BlockCatalog` -- no new
## mechanism needed. A row using it, ranked above the burn row, is "hold
## Immolate while my health is above 50%" and this proves that row actually
## drops a live sustain on the tick health crosses, not just in theory.
func test_a_self_hp_below_row_drops_a_live_immolate_sustain_on_the_crossing_tick() -> void:
	var immolate := ActionLibrary.get_action(IMMOLATE)
	var claw := ActionLibrary.get_action(&"abomination_claw")

	var stop_condition := SelfHpBelowBlock.new()
	stop_condition.fraction = 0.5
	var claw_block := UseActionBlock.new()
	claw_block.action = claw
	var stop_row := Plan.new()
	stop_row.id = &"stop_at_half_health"
	stop_row.condition = stop_condition
	stop_row.blocks = [TargetNearestEnemyBlock.new(), claw_block] as Array[PlanBlock]

	var burn_condition := EnemyInRangeBlock.new()
	burn_condition.range_units = immolate.sustain_radius
	var immolate_block := UseActionBlock.new()
	immolate_block.action = immolate
	var burn_row := Plan.new()
	burn_row.id = IMMOLATE_PLAN
	burn_row.condition = burn_condition
	burn_row.blocks = [TargetSelfBlock.new(), immolate_block] as Array[PlanBlock]

	var pawn := PawnData.new()
	pawn.id = &"p1"
	pawn.pawn_class = ClassLibrary.get_class_def(&"abomination")
	pawn.plans = [stop_row, burn_row]

	var caster := CombatUnit.new()
	caster.id = 0
	caster.team = CG.Team.PLAYER
	caster.pawn = pawn
	caster.actions = [&"abomination_claw", IMMOLATE]
	caster.hp_max = 1000
	caster.hp = 1000
	caster.resource_max = 100
	caster.resource = 100
	caster.resource_kind = CG.ResourceKind.RAGE
	caster.position = Vector2.ZERO

	var enemy := CombatUnit.new()
	enemy.id = 1
	enemy.team = CG.Team.ENEMY
	enemy.hp_max = 100000
	enemy.hp = 100000
	## Inside both Claw's 45-unit reach and Immolate's 90, so the only thing
	## deciding between the two rows is the hp condition.
	enemy.position = Vector2(40.0, 0.0)

	var state := CombatState.new(772)
	state.units.append(caster)
	state.units.append(enemy)
	var deps := SimDeps.new()

	## Immolate's own wind_up_ticks (15) has to complete before it ignites.
	for i in immolate.wind_up_ticks + 1:
		CombatSim.step(state, deps)
	assert_eq(caster.sustaining, IMMOLATE, "holding the aura above half health")

	caster.hp = int(caster.hp_max * 0.4)
	CombatSim.step(state, deps)

	assert_eq(caster.sustaining, &"", "the stop row took over on the tick hp crossed 50%")