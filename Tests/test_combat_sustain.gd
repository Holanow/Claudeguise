extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")

## Issue 61, the simulation half: an action a pawn HOLDS. It deals its effect
## and charges `sustain_cost_per_tick` on every tick, for as long as its
## decision layer keeps choosing it.
##
## Every assertion below is an exact count or an exact number, never `> 0`.
## Announcement rule 4: an `> 0` assertion on a count cannot warn, only fail, and
## it reads identically at six and at one. These fixtures are deterministic, so
## there is no reason to weaken any of them to an inequality.
##
## The negative tests are the ones worth reading twice --
## `test_a_fight_with_no_sustained_action_emits_no_sustain_events` and
## `test_no_authored_action_is_sustained_yet`. A mechanism that fires when it
## should not is worse than one that never fires, and the whole of this file
## would pass on a build where `sustain_cost_per_tick` was ignored and something
## else did the damage.

const _WIND_UP := 1
const _RADIUS := 50.0
const _COST := 3
const _POWER := 4.0

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.resource_max = 10
	u.resource = 10
	u.position = pos
	u.move_speed = 8.0
	return u

## `sustain_cost_per_tick > 0` is the only thing that makes an action sustained.
## `recover_ticks == 0` so the caster is free to re-affirm on every tick after
## ignition; a nonzero recovery is covered separately below.
func _aura(cost: int = _COST, radius: float = _RADIUS) -> ActionDef:
	var a := ActionDef.new()
	a.id = &"immolate"
	a.wind_up_ticks = _WIND_UP
	a.recover_ticks = 0
	a.range_units = 999.0
	a.damage_type = CG.DamageType.FIRE
	a.sustain_cost_per_tick = cost
	a.sustain_radius = radius
	return a

## `default_decide` returns "use this action" forever, which is what a plan whose
## condition still holds does. That IS the re-affirmation the channel lives on,
## so it has to come from the decision layer rather than from a hand-placed
## intent: a test that writes `unit.intent` directly never runs `_decide_phase`
## and would measure nothing.
func _deps(action: ActionDef, decide: Callable = Callable()) -> SimDeps:
	var by_id := {action.id: action}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return by_id.get(id)
	deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _r = null) -> float: return _POWER
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.resource_regen_per_tick = func(_u: CombatUnit) -> float: return 0.0
	deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.0
	## Only unit 0 channels. Everybody else idles, including the enemies -- a
	## `default_decide` that hands the same action to every unit had all four
	## casting the aura at each other, which is a fixture that measures four
	## overlapping mechanisms and calls the result one.
	var inner := decide
	if not inner.is_valid():
		inner = func(_s: CombatState, u: CombatUnit) -> Intent:
			return Intent.use_action(action.id, u.focus_id)
	deps.default_decide = func(s: CombatState, u: CombatUnit) -> Intent:
		if u.id != 0:
			return Intent.idle()
		return inner.call(s, u)
	return deps

func _count(state: CombatState, kind: CG.EventKind) -> int:
	var n := 0
	for e in state.events:
		if e.kind == kind:
			n += 1
	return n

func _first(state: CombatState, kind: CG.EventKind) -> CombatEvent:
	for e in state.events:
		if e.kind == kind:
			return e
	return null

## Caster at the origin, one enemy inside the radius, one far outside it, and
## one ally standing right next to the caster.
func _arena(action: ActionDef) -> CombatState:
	var state := CombatState.new(4242)
	var caster := _unit(0, CG.Team.PLAYER, 100, Vector2.ZERO)
	caster.focus_id = 1
	var near := _unit(1, CG.Team.ENEMY, 100, Vector2(30.0, 0.0))
	var far := _unit(2, CG.Team.ENEMY, 100, Vector2(200.0, 0.0))
	var ally := _unit(3, CG.Team.PLAYER, 100, Vector2(10.0, 0.0))
	state.units.append(caster)
	state.units.append(near)
	state.units.append(far)
	state.units.append(ally)
	return state

# ---------------------------------------------------------------------------
# it ticks, and it charges
# ---------------------------------------------------------------------------

func test_a_held_action_damages_every_tick_and_charges_every_tick() -> void:
	var action := _aura()
	var state := _arena(action)
	var deps := _deps(action)

	# Tick 1 commits and completes the 1-tick wind-up, so ignition and the first
	# tick of upkeep land together. Ticks 2 and 3 are pure upkeep.
	for i in 3:
		CombatSim.step(state, deps)

	var caster := state.unit(0)
	assert_eq(caster.sustaining, action.id, "the caster is still holding it")
	assert_eq(caster.resource, 10 - 3 * _COST, "charged once per tick, three ticks")
	assert_eq(state.unit(1).hp, 100 - 3 * int(_POWER), "the near enemy burned three times")
	assert_eq(_count(state, CG.EventKind.SUSTAIN_START), 1, "ignited exactly once")
	assert_eq(_count(state, CG.EventKind.SUSTAIN_END), 0, "and has not stopped")
	assert_eq(_count(state, CG.EventKind.RESOURCE_SPENT), 3, "one upkeep event per tick")
	assert_eq(_count(state, CG.EventKind.DAMAGE), 3, "one damage event per tick")

func test_the_effect_reaches_only_enemies_inside_the_radius() -> void:
	var action := _aura()
	var state := _arena(action)
	var deps := _deps(action)
	for i in 3:
		CombatSim.step(state, deps)

	assert_eq(state.unit(1).hp, 100 - 3 * int(_POWER), "30 units away, inside 50")
	assert_eq(state.unit(2).hp, 100, "200 units away, untouched")
	assert_eq(state.unit(3).hp, 100, "an ally at 10 units is never hit by a damage aura")

func test_a_held_action_puts_a_status_on_the_caster_for_its_whole_life() -> void:
	# The two events mark the ends of the channel; this is what marks the middle.
	# A badge on the unit for every tick it is holding is the difference between
	# an ability a player can watch and one they can only infer.
	var action := _aura()
	var state := _arena(action)
	var deps := _deps(action)

	CombatSim.step(state, deps)
	assert_true(state.unit(0).has_status(CG.Status.SUSTAINING), "badge on from tick one")
	CombatSim.step(state, deps)
	assert_true(state.unit(0).has_status(CG.Status.SUSTAINING), "and still on")

func test_ignition_does_not_report_a_miss() -> void:
	# A channel has no focused target to be in or out of range of. Running the
	# ordinary target resolution and ignoring the answer would write a MISS into
	# the combat log on every ignition, which is a false record rather than a
	# cosmetic one.
	var action := _aura()
	var state := _arena(action)
	state.unit(0).focus_id = -1
	var deps := _deps(action)
	for i in 3:
		CombatSim.step(state, deps)

	assert_eq(_count(state, CG.EventKind.MISS), 0, "no miss anywhere")
	assert_eq(state.unit(0).sustaining, action.id, "and it held with no target at all")

# ---------------------------------------------------------------------------
# what ends it: resource
# ---------------------------------------------------------------------------

func test_it_stops_when_the_resource_runs_out_and_the_last_tick_is_not_partial() -> void:
	# 10 resource at 3 per tick: three full ticks, then a fourth it cannot pay
	# for. Nothing is charged and nothing is dealt on that fourth tick -- the
	# caster is left holding 1, not 0.
	var action := _aura()
	var state := _arena(action)
	var deps := _deps(action)
	for i in 4:
		CombatSim.step(state, deps)

	var caster := state.unit(0)
	assert_eq(caster.resource, 1, "the remainder is not spent")
	assert_eq(caster.sustaining, &"", "and it is no longer holding")
	assert_false(caster.has_status(CG.Status.SUSTAINING), "badge gone with it")
	assert_eq(_count(state, CG.EventKind.RESOURCE_SPENT), 3, "three charges, not four")
	assert_eq(_count(state, CG.EventKind.DAMAGE), 3, "three ticks of damage, not four")
	assert_eq(_count(state, CG.EventKind.SUSTAIN_END), 1, "and it said so")

func test_the_end_event_carries_how_long_it_was_held() -> void:
	var action := _aura()
	var state := _arena(action)
	var deps := _deps(action)
	for i in 4:
		CombatSim.step(state, deps)

	var ended := _first(state, CG.EventKind.SUSTAIN_END)
	assert_true(ended != null, "an end event exists")
	assert_eq(ended.tick, 4, "it ended on the tick it could not pay for")
	assert_eq(ended.amount, 3, "held for three ticks")
	assert_eq(ended.action_id, action.id, "and names the action")
	assert_eq(ended.source_id, 0, "and the caster")

# ---------------------------------------------------------------------------
# what ends it: the plan stops choosing it
# ---------------------------------------------------------------------------

func test_it_stops_the_tick_the_decision_layer_chooses_something_else() -> void:
	# The design decision this whole mechanism turns on. A channel lives exactly
	# as long as the plan keeps choosing it, so a plan whose condition drops is
	# the off switch -- and the player can read and edit that condition, which is
	# what CLAUDE.md's binding principle asks for.
	var action := _aura(1)
	var ticks := [0]
	var decide := func(_s: CombatState, u: CombatUnit) -> Intent:
		ticks[0] += 1
		if ticks[0] <= 2:
			return Intent.use_action(action.id, u.focus_id)
		return Intent.move_to(Vector2(500.0, 0.0))
	var state := _arena(action)
	var deps := _deps(action, decide)

	for i in 4:
		CombatSim.step(state, deps)

	var caster := state.unit(0)
	assert_eq(caster.sustaining, &"", "stopped holding")
	assert_eq(_count(state, CG.EventKind.SUSTAIN_END), 1, "exactly one end")
	assert_eq(_count(state, CG.EventKind.RESOURCE_SPENT), 2, "charged only while chosen")
	assert_eq(_count(state, CG.EventKind.DAMAGE), 2, "and dealt only while chosen")
	assert_true(caster.position.x > 0.0, "and it walked away afterwards")

func test_re_choosing_a_held_action_does_not_re_commit_it() -> void:
	# Without the early return in `_resolve_use_action` this pays `resource_cost`
	# and restarts its wind-up every single tick, which would mean it never
	# actually ticks. One ACTION_START for the whole channel is the assertion
	# that catches that.
	var action := _aura(1)
	action.resource_cost = 2
	var state := _arena(action)
	var deps := _deps(action)
	for i in 5:
		CombatSim.step(state, deps)

	assert_eq(_count(state, CG.EventKind.ACTION_START), 1, "committed once")
	assert_eq(_count(state, CG.EventKind.ACTION_FIRE), 1, "fired once")
	assert_eq(_count(state, CG.EventKind.SUSTAIN_START), 1, "ignited once")
	# 2 on commit, then 1 per tick for five ticks.
	assert_eq(state.unit(0).resource, 10 - 2 - 5, "commit cost once, upkeep per tick")

func test_recovery_ticks_do_not_end_a_channel() -> void:
	# A unit in recovery is never asked for an intent, so it cannot re-affirm.
	# That must not read as "chose something else": recovery is the unit
	# finishing what it was told to do, not changing its mind.
	var action := _aura(1)
	action.recover_ticks = 3
	var state := _arena(action)
	var deps := _deps(action)
	for i in 3:
		CombatSim.step(state, deps)

	var caster := state.unit(0)
	assert_true(caster.recover_ticks_left > 0, "still recovering")
	assert_eq(caster.sustaining, action.id, "and still holding")
	assert_eq(_count(state, CG.EventKind.SUSTAIN_END), 0, "nothing ended it")
	assert_eq(_count(state, CG.EventKind.RESOURCE_SPENT), 3, "upkeep ran through recovery")

# ---------------------------------------------------------------------------
# what ends it: stun, and death
# ---------------------------------------------------------------------------

func test_a_stun_breaks_a_channel_even_though_it_does_not_cancel_a_wind_up() -> void:
	var action := _aura(1)
	var state := _arena(action)
	var deps := _deps(action)
	CombatSim.step(state, deps)
	assert_eq(state.unit(0).sustaining, action.id, "holding after ignition")

	state.unit(0).statuses[CG.Status.STUN] = 999
	CombatSim.step(state, deps)

	var caster := state.unit(0)
	assert_eq(caster.sustaining, &"", "the stun broke it")
	assert_eq(_count(state, CG.EventKind.SUSTAIN_END), 1, "and said so")
	assert_eq(_count(state, CG.EventKind.RESOURCE_SPENT), 1, "no upkeep on the stunned tick")

func test_a_channel_does_not_outlive_its_caster() -> void:
	# Killed by a real damage path (a poison tick) rather than by hand, because
	# the branch under test is the one that catches a death landing *after*
	# `_tick_sustain` has already run in the same loop body.
	var action := _aura(1)
	var state := _arena(action)
	var deps := _deps(action)
	deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 500.0
	CombatSim.step(state, deps)
	assert_eq(state.unit(0).sustaining, action.id, "holding")

	state.unit(0).statuses[CG.Status.POISON] = 999
	CombatSim.step(state, deps)

	var caster := state.unit(0)
	assert_false(caster.alive, "the poison killed it")
	assert_eq(caster.sustaining, &"", "and the channel died with it")
	var ended := _first(state, CG.EventKind.SUSTAIN_END)
	assert_eq(ended.tick, 2, "on the same tick it died, not the tick after")

# ---------------------------------------------------------------------------
# geometry and generality
# ---------------------------------------------------------------------------

func test_a_wall_spares_a_target_when_the_action_asks_for_line_of_sight() -> void:
	var action := _aura(1)
	action.requires_line_of_sight = true
	var state := _arena(action)
	state.terrain = [Terrain.make(Terrain.Kind.WALL, Rect2(15.0, -40.0, 6.0, 80.0))]
	var deps := _deps(action)
	for i in 3:
		CombatSim.step(state, deps)

	assert_eq(state.unit(1).hp, 100, "the wall stands between them")
	assert_eq(state.unit(0).sustaining, action.id, "the channel itself is unaffected")

func test_a_sustained_heal_reaches_allies_rather_than_enemies() -> void:
	# `heals` picks the side, the same field that already decides whether an
	# ordinary effect adds or subtracts hp. That is what makes this a category
	# rather than one class's ability.
	var action := _aura(1)
	action.heals = true
	var state := _arena(action)
	state.unit(3).hp = 50
	var deps := _deps(action)
	for i in 3:
		CombatSim.step(state, deps)

	assert_eq(state.unit(3).hp, 50 + 3 * int(_POWER), "the ally was healed each tick")
	assert_eq(state.unit(1).hp, 100, "and the enemy beside it was not touched")
	# Three, not six: the caster is inside its own aura and is at full hp, and
	# `_apply_action_effect` has always declined to emit a HEAL that heals
	# nothing. Worth stating rather than adjusting to, because it is why the
	# count is what it is.
	assert_eq(_count(state, CG.EventKind.HEAL), 3, "one per tick, the ally only")

func test_a_channel_with_no_radius_reaches_nobody_rather_than_falling_back() -> void:
	# Content authored wrong should look wrong. Silently retargeting a
	# zero-radius channel at the focused unit would hide the mistake.
	var action := _aura(1, 0.0)
	var state := _arena(action)
	var deps := _deps(action)
	for i in 3:
		CombatSim.step(state, deps)

	assert_eq(_count(state, CG.EventKind.DAMAGE), 0, "nothing was reached")
	assert_eq(_count(state, CG.EventKind.RESOURCE_SPENT), 3, "and it still cost the caster")

func test_the_same_seed_produces_the_same_channel_twice() -> void:
	var a := []
	for run in 2:
		var action := _aura(1)
		var state := _arena(action)
		var deps := _deps(action)
		for i in 6:
			CombatSim.step(state, deps)
		var trace := ""
		for e in state.events:
			trace += "%d:%d:%d:%d:%d;" % [e.kind, e.tick, e.source_id, e.target_id, e.amount]
		a.append(trace)
	assert_eq(a[0], a[1], "identical event streams")
	assert_true(a[0].length() > 0, "and the streams are not both empty")

# ---------------------------------------------------------------------------
# the negative side: it stays quiet where it should
# ---------------------------------------------------------------------------

func test_a_fight_with_no_sustained_action_emits_no_sustain_events() -> void:
	# The detector fed known-good input. Every action in the game today has
	# `sustain_cost_per_tick == 0`, and this asserts the whole mechanism is
	# inert for them -- no events, no status, no upkeep.
	var plain := ActionDef.new()
	plain.id = &"strike"
	plain.wind_up_ticks = _WIND_UP
	plain.range_units = 999.0
	var state := _arena(plain)
	var deps := _deps(plain)
	for i in 6:
		CombatSim.step(state, deps)

	assert_eq(_count(state, CG.EventKind.SUSTAIN_START), 0, "nothing ignited")
	assert_eq(_count(state, CG.EventKind.SUSTAIN_END), 0, "nothing ended")
	assert_eq(_count(state, CG.EventKind.RESOURCE_SPENT), 0, "nothing was charged")
	assert_eq(state.unit(0).sustaining, &"", "and nothing is held")
	assert_false(state.unit(0).has_status(CG.Status.SUSTAINING), "and no badge")

## **This tripwire fired, as swift built it to.** It used to assert that no
## authored action was sustained and its own comment named the moment: *"when
## finch's Immolate lands this test fails, and that is what it is for."* Issue
## 219 is that moment, so the assertion is replaced with its live form rather
## than deleted -- the property worth guarding was never "nothing is sustained",
## it was "we know exactly what is".
##
## Exactly one, and it is named. A second sustained action is not forbidden, but
## it changes what every measurement in the pull request that landed the first
## one means, so it should arrive with somebody looking at this line.
func test_immolate_is_the_one_authored_sustained_action() -> void:
	var sustained: Array[StringName] = []
	for id in Registry.all_action_ids():
		if Registry.get_action(id).sustain_cost_per_tick > 0:
			sustained.append(id)
	assert_eq(sustained.size(), 1, "sustained actions authored: %s" % [sustained])
	assert_true(
		sustained.has(&"abomination_immolate"),
		"the sustained action should be Immolate, got %s" % [sustained]
	)

func test_a_sustained_action_is_authored_with_a_reach_and_without_a_cooldown() -> void:
	# Two ways to author one that quietly does nothing:
	#   - a cost with no radius: charges the caster and reaches nobody.
	#   - a cooldown: `PlanInterpreter.can_afford` refuses to re-choose it, so
	#     the channel ends itself on the first free tick after ignition.
	# Vacuously true today, and it is the guard that catches either one the
	# first time content writes it. The registry assertion is not decoration:
	# without it this method records zero assertions, and a check that walks an
	# empty list is indistinguishable from a check that passed.
	var ids := Registry.all_action_ids()
	assert_true(ids.size() > 0, "there are actions to check at all")
	for id in ids:
		var a := Registry.get_action(id)
		if a.sustain_cost_per_tick <= 0:
			continue
		assert_true(a.sustain_radius > 0.0, "'%s' costs per tick and reaches nothing" % id)
		assert_eq(a.cooldown_ticks, 0, "'%s' is sustained and on a cooldown" % id)
