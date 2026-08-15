extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")

## Issues 130 and 121: a status that remembers something beyond when it ends.
##
## One mechanism, `CombatUnit.status_magnitude`, two meanings decided per status:
## BLEED counts stacks, BURN carries the damage of the hit that applied it. The
## same stored number is read at both ends for BURN -- it sets how hard the burn
## ticks and what consuming the burn pays.
##
## THE TESTS THAT MATTER MOST are the inert ones at the bottom. Every seam here
## defaults to a value that makes the new arithmetic vanish, and that is a
## stronger claim than "no content wires it yet": the damage rate feeds
## `_stochastic_round`, which draws from the fight's shared rng, so a rate that
## moved by any amount would change the outcome of every fight in the game
## rather than only the afflicted ones.
##
## Every assertion is an exact number. Announcement rule 4: these fixtures are
## deterministic, so an inequality would only hide drift.

const _SEED := 5150

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.resource_max = 100
	u.resource = 100
	u.position = pos
	u.move_speed = 8.0
	return u

## Attacker at the origin, target one unit away, and nothing decides anything on
## its own -- the tests place intents by hand so the fixture measures the effect
## and not a decision layer.
func _arena() -> CombatState:
	var state := CombatState.new(_SEED)
	state.units.append(_unit(0, CG.Team.PLAYER, 200, Vector2.ZERO))
	state.units.append(_unit(1, CG.Team.ENEMY, 200, Vector2(1.0, 0.0)))
	return state

func _hit(id: StringName, status: CG.Status, duration: int, power: float) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 0
	a.recover_ticks = 0
	a.range_units = 999.0
	a.damage_type = CG.DamageType.PHYSICAL
	a.power_scale = power
	a.applies_status = status
	a.applies_status_enabled = true
	a.status_duration_ticks = duration
	return a

func _deps(actions: Array, power: float = 10.0) -> SimDeps:
	var by_id := {}
	for a in actions:
		by_id[a.id] = a
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return by_id.get(id)
	deps.attack_power = func(_u: CombatUnit, a: ActionDef, _r = null) -> float: return power * a.power_scale
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.resource_regen_per_tick = func(_u: CombatUnit) -> float: return 0.0
	deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.0
	## Pinned rather than left on the shipped defaults, because those are no
	## longer uniform: BLEED now carries live placeholder numbers (a 5-tick
	## rhythm and a decay window) so the mechanism is not dead on arrival for
	## the first action that applies it. Every fixture in this file is about the
	## magnitude arithmetic, so it pins the rhythm and the decay to the neutral
	## values and measures one thing at a time. `Tests/test_combat_bleed_is_live.gd`
	## is where the shipped defaults themselves are asserted.
	deps.status_tick_interval = func(_s: CG.Status) -> int: return 1
	deps.status_stack_decay_ticks = func(_s: CG.Status) -> int: return 0
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
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

## Fires `action` from unit 0 at unit 1 on this tick.
func _strike(state: CombatState, deps: SimDeps, action: ActionDef) -> void:
	state.unit(0).intent = Intent.use_action(action.id, 1)
	CombatSim.step(state, deps)

# ---------------------------------------------------------------------------
# BLEED: stacks
# ---------------------------------------------------------------------------

func test_bleed_stacks_where_every_other_status_refreshes() -> void:
	var cut := _hit(&"cut", CG.Status.BLEED, 999, 1.0)
	var state := _arena()
	var deps := _deps([cut])

	for _i in 3:
		_strike(state, deps, cut)

	var target := state.unit(1)
	assert_eq(target.status_magnitude.get(CG.Status.BLEED, 0.0), 3.0, "three hits, three stacks")
	assert_true(target.has_status(CG.Status.BLEED), "and it is carrying the status")

func test_a_non_stacking_status_still_only_refreshes() -> void:
	var jab := _hit(&"jab", CG.Status.POISON, 999, 1.0)
	var state := _arena()
	var deps := _deps([jab])

	for _i in 3:
		_strike(state, deps, jab)

	assert_eq(state.unit(1).status_magnitude.get(CG.Status.POISON, 0.0), 0.0,
		"poison stores nothing: three applications, no accumulation")

func test_bleed_damage_is_per_tick_per_stack() -> void:
	var cut := _hit(&"cut", CG.Status.BLEED, 999, 1.0)
	var state := _arena()
	var deps := _deps([cut])
	deps.status_damage_per_magnitude = func(_u: CombatUnit, _s: CG.Status) -> float: return 2.0

	_strike(state, deps, cut) # tick 1: 10 damage from the hit, then 1 stack x 2
	var target := state.unit(1)
	assert_eq(target.hp, 200 - 10 - 2, "one stack bleeds for 2 on the tick it lands")

	_strike(state, deps, cut) # tick 2: another 10, now 2 stacks x 2
	assert_eq(target.hp, 200 - 10 - 2 - 10 - 4, "two stacks bleed for 4")

	CombatSim.step(state, deps) # tick 3: no hit, still 2 stacks
	assert_eq(target.hp, 200 - 10 - 2 - 10 - 4 - 4, "and keep bleeding for 4")

func test_bleed_can_tick_less_often_than_poison() -> void:
	var cut := _hit(&"cut", CG.Status.BLEED, 999, 1.0)
	var state := _arena()
	var deps := _deps([cut])
	deps.status_damage_per_magnitude = func(_u: CombatUnit, _s: CG.Status) -> float: return 3.0
	deps.status_tick_interval = func(s: CG.Status) -> int: return 5 if s == CG.Status.BLEED else 1

	_strike(state, deps, cut) # tick 1: hit for 10; 1 % 5 != 0, so no bleed tick
	var target := state.unit(1)
	assert_eq(target.hp, 190, "the tick it lands on is not a bleed tick")

	for _i in 4: # ticks 2-5; only tick 5 is a multiple of 5
		CombatSim.step(state, deps)
	assert_eq(target.hp, 187, "exactly one bleed tick in five")

	for _i in 5: # ticks 6-10
		CombatSim.step(state, deps)
	assert_eq(target.hp, 184, "and one more in the next five")

## The decay curve the player will read off the badge: 3, 2, 1, gone -- not nine
## stacks disappearing in a single frame the tick their source dies.
func test_stacks_fall_off_one_at_a_time_when_content_asks_for_it() -> void:
	var cut := _hit(&"cut", CG.Status.BLEED, 2, 1.0)
	var state := _arena()
	var deps := _deps([cut])
	deps.status_stack_decay_ticks = func(_s: CG.Status) -> int: return 3 # over the pin in _deps

	_strike(state, deps, cut)
	_strike(state, deps, cut)
	_strike(state, deps, cut)
	var target := state.unit(1)
	assert_eq(target.status_magnitude.get(CG.Status.BLEED, 0.0), 3.0, "three stacks up")

	for _i in 3:
		CombatSim.step(state, deps)
	assert_eq(target.status_magnitude.get(CG.Status.BLEED, 0.0), 2.0, "one came off")
	assert_true(target.has_status(CG.Status.BLEED), "and the status survived it")
	assert_eq(_count(state, CG.EventKind.STATUS_EXPIRED), 0, "a dropped stack is not an expiry")

	for _i in 3:
		CombatSim.step(state, deps)
	assert_eq(target.status_magnitude.get(CG.Status.BLEED, 0.0), 1.0, "and another")

	for _i in 3:
		CombatSim.step(state, deps)
	assert_false(target.has_status(CG.Status.BLEED), "the last stack takes the status with it")
	assert_eq(target.status_magnitude.has(CG.Status.BLEED), false, "and leaves no phantom count behind")
	assert_eq(_count(state, CG.EventKind.STATUS_EXPIRED), 1, "which IS an expiry, exactly once")

## With no decay window authored, the whole thing comes off at once -- the
## refresh behaviour every status had before stacking existed.
func test_without_a_decay_window_every_stack_falls_off_together() -> void:
	var cut := _hit(&"cut", CG.Status.BLEED, 2, 1.0)
	var state := _arena()
	var deps := _deps([cut])

	_strike(state, deps, cut)
	_strike(state, deps, cut)
	_strike(state, deps, cut)
	for _i in 3:
		CombatSim.step(state, deps)

	var target := state.unit(1)
	assert_false(target.has_status(CG.Status.BLEED), "gone")
	assert_eq(target.status_magnitude.has(CG.Status.BLEED), false, "and the count with it")

# ---------------------------------------------------------------------------
# BURN: the hit that applied it
# ---------------------------------------------------------------------------

func test_burn_remembers_the_damage_of_the_hit_that_applied_it() -> void:
	var scald := _hit(&"scald", CG.Status.BURN, 999, 4.0) # 10 base x 4 = 40
	var state := _arena()
	var deps := _deps([scald])

	_strike(state, deps, scald)
	assert_eq(state.unit(1).status_magnitude.get(CG.Status.BURN, 0.0), 40.0,
		"the burn is worth what the hit dealt")

func test_burn_damage_per_tick_scales_off_that_hit() -> void:
	var weak := _hit(&"weak_scald", CG.Status.BURN, 999, 1.0)  # deals 10
	var big := _hit(&"big_scald", CG.Status.BURN, 999, 4.0)    # deals 40

	var soft := _arena()
	var soft_deps := _deps([weak])
	soft_deps.status_damage_per_magnitude = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.1
	_strike(soft, soft_deps, weak)
	assert_eq(soft.unit(1).hp, 200 - 10 - 1, "a 10 hit burns for 1 a tick")

	var hard := _arena()
	var hard_deps := _deps([big])
	hard_deps.status_damage_per_magnitude = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.1
	_strike(hard, hard_deps, big)
	assert_eq(hard.unit(1).hp, 200 - 40 - 4, "a 40 hit burns for 4 a tick")

## THE RE-APPLICATION DECISION. A weaker follow-up refreshes the duration and
## must NOT dilute the burn: overwriting downward means the player lands a second
## fire attack and their burn gets worse, and it would silently devalue a combo
## they had already planned around.
func test_a_weaker_hit_refreshes_a_burn_without_diluting_it() -> void:
	var weak := _hit(&"weak_scald", CG.Status.BURN, 20, 1.0)
	var big := _hit(&"big_scald", CG.Status.BURN, 20, 4.0)
	var state := _arena()
	var deps := _deps([weak, big])

	_strike(state, deps, big)
	assert_eq(state.unit(1).status_magnitude.get(CG.Status.BURN, 0.0), 40.0)

	_strike(state, deps, weak)
	assert_eq(state.unit(1).status_magnitude.get(CG.Status.BURN, 0.0), 40.0,
		"the weak hit did not lower it")
	assert_eq(int(state.unit(1).statuses[CG.Status.BURN]), 22, "but did refresh the duration")

func test_a_stronger_hit_does_raise_a_burn() -> void:
	var weak := _hit(&"weak_scald", CG.Status.BURN, 20, 1.0)
	var big := _hit(&"big_scald", CG.Status.BURN, 20, 4.0)
	var state := _arena()
	var deps := _deps([weak, big])

	_strike(state, deps, weak)
	_strike(state, deps, big)
	assert_eq(state.unit(1).status_magnitude.get(CG.Status.BURN, 0.0), 40.0, "max, not first-wins")

## Armour matters twice on purpose: a well-armoured target takes a small hit and
## therefore a small burn. The stored number is the mitigated damage, which is
## the figure the player watched land.
func test_the_stored_burn_is_the_mitigated_damage_not_the_raw_roll() -> void:
	var scald := _hit(&"scald", CG.Status.BURN, 999, 4.0)
	var state := _arena()
	var deps := _deps([scald])
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.25

	_strike(state, deps, scald)
	assert_eq(state.unit(1).status_magnitude.get(CG.Status.BURN, 0.0), 30.0,
		"40 raw, 25% off, 30 dealt and 30 stored")
	var e := _first(state, CG.EventKind.DAMAGE)
	assert_eq(e.amount, 30, "and it matches the number on screen")

# ---------------------------------------------------------------------------
# the combo: one stored number read at both ends
# ---------------------------------------------------------------------------

func _consumer(id: StringName, status: CG.Status, scale: float) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 0
	a.recover_ticks = 0
	a.range_units = 999.0
	a.damage_type = CG.DamageType.FIRE
	a.power_scale = 1.0
	a.consumes_status = status
	a.consumes_status_enabled = true
	a.consumed_power_scale = scale
	return a

func test_consuming_a_burn_pays_out_by_how_hard_the_burn_was() -> void:
	var scald := _hit(&"scald", CG.Status.BURN, 999, 4.0) # deals 40, stores 40
	var blast := _consumer(&"blast", CG.Status.BURN, 0.5) # 10 base + 0.5 x 40
	var state := _arena()
	var deps := _deps([scald, blast])

	_strike(state, deps, scald)
	assert_eq(state.unit(1).hp, 160)

	_strike(state, deps, blast)
	var target := state.unit(1)
	assert_eq(target.hp, 160 - 30, "10 of its own plus half of a 40 burn")
	assert_false(target.has_status(CG.Status.BURN), "and the burn is eaten")
	assert_eq(target.status_magnitude.has(CG.Status.BURN), false, "magnitude gone with it")

func test_a_bigger_scald_makes_a_bigger_blast() -> void:
	var weak := _hit(&"weak_scald", CG.Status.BURN, 999, 1.0) # stores 10
	var big := _hit(&"big_scald", CG.Status.BURN, 999, 4.0)   # stores 40
	var blast := _consumer(&"blast", CG.Status.BURN, 0.5)

	var soft := _arena()
	var soft_deps := _deps([weak, blast])
	_strike(soft, soft_deps, weak)
	_strike(soft, soft_deps, blast)

	var hard := _arena()
	var hard_deps := _deps([big, blast])
	_strike(hard, hard_deps, big)
	_strike(hard, hard_deps, blast)

	assert_eq(200 - soft.unit(1).hp, 10 + 15, "weak scald: 10, then 10 + half of 10")
	assert_eq(200 - hard.unit(1).hp, 40 + 30, "big scald: 40, then 10 + half of 40")

## The consume lands inside ONE damage event. Two lines for one hit is the same
## fact told twice, and a player counting damage would read it as two hits.
func test_the_consume_bonus_lands_inside_the_one_damage_event() -> void:
	var scald := _hit(&"scald", CG.Status.BURN, 999, 4.0)
	var blast := _consumer(&"blast", CG.Status.BURN, 0.5)
	var state := _arena()
	var deps := _deps([scald, blast])

	_strike(state, deps, scald)
	var before := state.events.size()
	_strike(state, deps, blast)

	var damage_events := 0
	var consumed: CombatEvent = null
	var damage: CombatEvent = null
	for i in range(before, state.events.size()):
		var e: CombatEvent = state.events[i]
		if e.kind == CG.EventKind.DAMAGE:
			damage_events += 1
			damage = e
		elif e.kind == CG.EventKind.STATUS_EXPIRED:
			consumed = e
	assert_eq(damage_events, 1, "one hit, one damage event")
	assert_eq(damage.amount, 30, "carrying the whole figure")
	assert_not_null(consumed, "and the consume said so")
	assert_eq(consumed.status, CG.Status.BURN)
	assert_eq(consumed.source_id, 0, "naming the caster, not an anonymous expiry")
	assert_eq(consumed.action_id, blast.id, "and the action that ate it")

func test_consuming_a_burn_that_is_not_there_pays_nothing() -> void:
	var blast := _consumer(&"blast", CG.Status.BURN, 0.5)
	var state := _arena()
	var deps := _deps([blast])

	_strike(state, deps, blast)
	assert_eq(state.unit(1).hp, 190, "just the action's own 10")
	assert_eq(_count(state, CG.EventKind.STATUS_EXPIRED), 0, "and nothing claimed to be consumed")

func test_a_consumed_bleed_is_eaten_whole() -> void:
	var cut := _hit(&"cut", CG.Status.BLEED, 999, 1.0)
	var rend := _consumer(&"rend", CG.Status.BLEED, 3.0)
	var state := _arena()
	var deps := _deps([cut, rend])

	for _i in 4:
		_strike(state, deps, cut)
	var hp_before := state.unit(1).hp
	_strike(state, deps, rend)

	assert_eq(hp_before - state.unit(1).hp, 10 + 12, "10 of its own plus 3 per stack of four")
	assert_false(state.unit(1).has_status(CG.Status.BLEED), "every stack, not one of them")

# ---------------------------------------------------------------------------
# a cleanse takes the memory with it
# ---------------------------------------------------------------------------

## Erasing the expiry and leaving the magnitude would leave nine stacks of bleed
## sitting on a unit that no longer has bleed, ready to be revived at full
## strength by the next application.
func test_a_cleanse_removes_the_stored_magnitude_too() -> void:
	var cut := _hit(&"cut", CG.Status.BLEED, 999, 1.0)
	var cleanse := ActionDef.new()
	cleanse.id = &"cleanse"
	cleanse.range_units = 999.0
	cleanse.heals = true
	cleanse.cleanses_harmful = true

	var state := _arena()
	var deps := _deps([cut, cleanse])
	for _i in 5:
		_strike(state, deps, cut)
	assert_eq(state.unit(1).status_magnitude.get(CG.Status.BLEED, 0.0), 5.0)

	state.unit(0).intent = Intent.use_action(cleanse.id, 1)
	CombatSim.step(state, deps)

	var target := state.unit(1)
	assert_false(target.has_status(CG.Status.BLEED), "cleansed")
	assert_eq(target.status_magnitude.has(CG.Status.BLEED), false, "no phantom stacks left")

	_strike(state, deps, cut)
	assert_eq(target.status_magnitude.get(CG.Status.BLEED, 0.0), 1.0,
		"and a fresh application starts from one, not from six")

# ---------------------------------------------------------------------------
# the count reaches the screen
# ---------------------------------------------------------------------------

func test_status_applied_carries_the_resulting_magnitude() -> void:
	var cut := _hit(&"cut", CG.Status.BLEED, 999, 1.0)
	var scald := _hit(&"scald", CG.Status.BURN, 999, 4.0)
	var state := _arena()
	var deps := _deps([cut, scald])

	_strike(state, deps, cut)
	_strike(state, deps, cut)
	_strike(state, deps, scald)

	var amounts: Array[int] = []
	for e in state.events:
		if e.kind == CG.EventKind.STATUS_APPLIED:
			amounts.append(e.amount)
	assert_eq(amounts, [1, 2, 40] as Array[int],
		"first stack, second stack, then a burn worth its hit")

# ---------------------------------------------------------------------------
# INERT: nothing above changes a single fight until content wires a number
# ---------------------------------------------------------------------------

## NARROWED, and saying so rather than quietly editing it. This asserted that
## every seam was inert for every status, which was true when written and is no
## longer: BLEED carries live placeholder numbers so its stacking mechanism is
## not dead on arrival. It is my own test and it encoded a state the project has
## deliberately left, not a property that still holds.
##
## What it always meant is intact and is the half that matters -- the statuses
## content can actually reach are untouched, so no fight in the game moves.
## `Tests/test_combat_bleed_is_live.gd` asserts the BLEED side, including that
## the placeholder reaches no other status.
## **BURN left this list on issue 121.** finch, rewritten rather than loosened:
## POISON is still the whole point -- it is reachable, it stores no magnitude, and
## a rate that moved for it would move every fight in the game. BURN is now live
## and is asserted so in `test_a_burn_pays_from_the_hit_that_lit_it` below.
func test_the_seams_stay_inert_for_every_status_content_can_reach() -> void:
	var deps := SimDeps.new()
	var unit := _unit(0, CG.Team.PLAYER, 10, Vector2.ZERO)
	assert_true(float(deps.status_damage_per_magnitude.call(unit, CG.Status.BURN)) > 0.0,
		"BURN should now draw from the hit that lit it")
	for status in [CG.Status.POISON]:
		assert_almost_eq(float(deps.status_damage_per_magnitude.call(unit, status)), 0.0,
			0.0001, "magnitude contributes no damage")
		assert_eq(int(deps.status_tick_interval.call(status)), 1, "still ticks every tick")
		assert_eq(int(deps.status_stack_decay_ticks.call(status)), 0, "and does not linger")

## **Inverted on issue 121.** swift wrote this as "the magnitude is stored, it
## simply does not pay yet". It pays now, so the same fixture proves the other
## direction: two burns identical except for the hit that lit them must not deal
## the same damage. finch, rewritten rather than loosened.
##
## Compared against a second arena rather than against an arithmetic expectation
## typed here, because the rate runs through `_stochastic_round` and a hand-
## computed number would only ever agree with my own reading of the rounding.
func test_a_burn_pays_from_the_hit_that_lit_it() -> void:
	var scald := _hit(&"scald", CG.Status.BURN, 999, 4.0)
	var small := _arena()
	var big := _arena()
	var small_deps := _deps([scald])
	var big_deps := _deps([scald])
	small_deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.0
	big_deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.0
	small_deps.status_damage_per_magnitude = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.0
	big_deps.status_damage_per_magnitude = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.02

	_strike(small, small_deps, scald)
	_strike(big, big_deps, scald)
	assert_eq(small.unit(1).status_magnitude.get(CG.Status.BURN, 0.0), 40.0,
		"the hit's mitigated damage is what gets stored")

	for _i in 40:
		CombatSim.step(small, small_deps)
		CombatSim.step(big, big_deps)
	assert_true(big.unit(1).hp < small.unit(1).hp,
		"a live per-magnitude rate must actually cost the burning unit health")

## The rng check, and the reason it is not paranoia: the damage rate feeds
## `_stochastic_round`, so a rate that moved by any amount at all would consume
## the shared stream differently and change every fight in the game.
## finch, issue 121: **the subject moved from BURN to POISON and the claim is
## unchanged.** This asserts that a status which stores no magnitude draws nothing
## extra from the shared stream. BURN was the right subject while its magnitude
## was inert; POISON is the one that is still reachable and still stores nothing,
## so it is now what protects every fight in the game from this seam.
func test_the_default_seams_consume_the_rng_exactly_as_before() -> void:
	var scald := _hit(&"scald", CG.Status.POISON, 999, 4.0)
	var state := _arena()
	var deps := _deps([scald])
	deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.0

	_strike(state, deps, scald)
	for _i in 20:
		CombatSim.step(state, deps)

	var fresh := RandomNumberGenerator.new()
	fresh.seed = _SEED
	assert_eq(state.rng.randf(), fresh.randf(),
		"a poison, which stores no magnitude, drew nothing extra from the fight's rng")

## And the proof that check can fail: a live per-magnitude rate on a fractional
## amount does reach `_stochastic_round`, and the streams come apart.
func test_a_live_magnitude_rate_does_consume_the_rng() -> void:
	var scald := _hit(&"scald", CG.Status.BURN, 999, 4.0)
	var inert := _arena()
	var live := _arena()
	var inert_deps := _deps([scald])
	inert_deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.0
	# finch, issue 121: the inert arm now has to say so explicitly. BURN's default
	# magnitude rate is live, so without this override both arms are live, the two
	# streams match, and this test quietly stops proving anything.
	inert_deps.status_damage_per_magnitude = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.0
	var live_deps := _deps([scald])
	live_deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.0
	live_deps.status_damage_per_magnitude = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.011

	_strike(inert, inert_deps, scald)
	_strike(live, live_deps, scald)
	for _i in 20:
		CombatSim.step(inert, inert_deps)
		CombatSim.step(live, live_deps)

	assert_ne(live.rng.randf(), inert.rng.randf(), "so the test above is not inert")

## No authored action consumes a status yet. This is what fails on the day
## content wires it, which is exactly when the balance table needs re-measuring
## -- rather than a comment that rots.
##
## **The stacking half of this fired and is gone, on #130.** It read
## "nothing applies BLEED yet, so nothing stacks in a real fight", and
## `rat_bite` in `floor1_enemies.gd` is what made it false. That is the
## assertion doing its job, not breaking: it named the moment and the
## re-measurement is in that pull request. Deleted rather than loosened, and
## only that one -- the consume half is finch's BURN/Blast combo and is still
## true.
## **The consume half fired on issue 121 and is inverted, as its own message
## asked for: "this is what fails on the day content wires it, which is exactly
## when the balance table needs re-measuring".** `geyser_blast` is what failed it,
## and the re-measurement is in that pull request -- the combo goes from 0 to 52
## consumes in 127 burns.
##
## Kept rather than deleted, pointing the other way: **exactly one action consumes
## a status.** A second one appearing is the next moment the table needs
## re-measuring, and this is the assertion that will say so.
func test_exactly_one_authored_action_consumes_a_status() -> void:
	var consuming: Array[StringName] = []
	for id in Registry.all_action_ids():
		var a: ActionDef = Registry.get_action(id)
		if a == null:
			continue
		if a.consumes_status_enabled:
			consuming.append(id)
	assert_eq(consuming.size(), 1,
		"expected only geyser_blast to consume a status, got %s -- if that is deliberate, re-measure the balance table and update this count" % str(consuming))
	assert_true(consuming.has(&"geyser_blast"), "the consumer should be Blast, got %s" % str(consuming))

# ---------------------------------------------------------------------------
# determinism
# ---------------------------------------------------------------------------

func test_two_runs_from_one_seed_stack_and_burn_identically() -> void:
	var cut := _hit(&"cut", CG.Status.BLEED, 40, 1.0)
	var scald := _hit(&"scald", CG.Status.BURN, 40, 4.0)
	var blast := _consumer(&"blast", CG.Status.BURN, 0.5)

	var play := func() -> CombatState:
		var state := _arena()
		var deps := _deps([cut, scald, blast])
		deps.status_damage_per_magnitude = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.07
		deps.status_stack_decay_ticks = func(_s: CG.Status) -> int: return 4
		_strike(state, deps, cut)
		_strike(state, deps, cut)
		_strike(state, deps, scald)
		for _i in 10:
			CombatSim.step(state, deps)
		_strike(state, deps, blast)
		for _i in 30:
			CombatSim.step(state, deps)
		return state

	var a: CombatState = play.call()
	var b: CombatState = play.call()
	assert_eq(a.unit(1).hp, b.unit(1).hp, "same seed, same fight")
	assert_eq(a.events.size(), b.events.size(), "and the same event stream")
