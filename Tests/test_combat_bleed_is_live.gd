extends "res://Tests/TestCase.gd"


## #130's other half: BLEED had a stacking mechanism sitting on top of an effect
## with no base. It was in `CombatSim._DOT_STATUSES` and multiplied correctly,
## and it multiplied **zero**, because `Balance.status_damage_per_tick` has no
## BLEED case and every magnitude seam defaulted to inert.

const _SEED := 6100

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.position = pos
	u.move_speed = 8.0
	return u

func _arena() -> CombatState:
	var state := CombatState.new(_SEED)
	state.units.append(_unit(0, CG.Team.PLAYER, 500, Vector2.ZERO))
	state.units.append(_unit(1, CG.Team.ENEMY, 500, Vector2(1.0, 0.0)))
	return state

## The REAL SimDeps, with only the decision layer stubbed out so the fixture
## does not depend on plans or content actions. Every rate below is the shipped
## default, which is what this file exists to measure.
func _real_deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	deps.plan_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return null
	return deps

func _run(state: CombatState, deps: SimDeps, ticks: int) -> void:
	for _i in ticks:
		CombatSim.step(state, deps)

# ---------------------------------------------------------------------------
# it does something now
# ---------------------------------------------------------------------------

func test_one_stack_of_bleed_actually_deals_damage() -> void:
	var state := _arena()
	var target := state.unit(1)
	target.statuses[CG.Status.BLEED] = 999
	target.status_magnitude[CG.Status.BLEED] = 1.0

	_run(state, _real_deps(), 10)

	assert_ne(target.hp, 500, "BLEED must not be a status that multiplies zero")
	assert_eq(target.hp, 498, "two bleed ticks in ten, one damage each")

func test_bleed_damage_multiplies_by_the_stack_count() -> void:
	var one := _arena()
	one.unit(1).statuses[CG.Status.BLEED] = 999
	one.unit(1).status_magnitude[CG.Status.BLEED] = 1.0

	var four := _arena()
	four.unit(1).statuses[CG.Status.BLEED] = 999
	four.unit(1).status_magnitude[CG.Status.BLEED] = 4.0

	_run(one, _real_deps(), 30)
	_run(four, _real_deps(), 30)

	assert_eq(500 - one.unit(1).hp, 6, "six ticks at one stack")
	assert_eq(500 - four.unit(1).hp, 24, "and four times that at four stacks")

## The player's *"does damage less often"*. POISON hits every tick; BLEED does
## not, and a player can tell them apart by rhythm without reading a number.
func test_bleed_ticks_less_often_than_poison() -> void:
	var deps := _real_deps()
	assert_eq(int(deps.status_tick_interval.call(CG.Status.BLEED)), 5, "bleed drips")
	assert_eq(int(deps.status_tick_interval.call(CG.Status.POISON)), 1, "poison does not")

	var state := _arena()
	var target := state.unit(1)
	target.statuses[CG.Status.BLEED] = 999
	target.status_magnitude[CG.Status.BLEED] = 1.0

	_run(state, deps, 4)
	assert_eq(target.hp, 500, "nothing in the first four ticks")
	_run(state, deps, 1)
	assert_eq(target.hp, 499, "and one on the fifth")

## Stacks decay one at a time under the shipped defaults, rather than the whole
## status vanishing the tick its source stops applying it.
func test_stacks_decay_one_at_a_time_under_the_shipped_defaults() -> void:
	var state := _arena()
	var target := state.unit(1)
	target.statuses[CG.Status.BLEED] = 2
	target.status_magnitude[CG.Status.BLEED] = 3.0

	_run(state, _real_deps(), 2)
	assert_eq(target.status_magnitude.get(CG.Status.BLEED, 0.0), 2.0, "one came off")
	assert_true(target.has_status(CG.Status.BLEED), "and the status held")

	_run(state, _real_deps(), 30)
	assert_eq(target.status_magnitude.get(CG.Status.BLEED, 0.0), 1.0, "and another")

	_run(state, _real_deps(), 30)
	assert_false(target.has_status(CG.Status.BLEED), "the last stack takes it with it")

func test_a_bleed_tick_emits_a_damage_event_carrying_the_status() -> void:
	var state := _arena()
	var target := state.unit(1)
	target.statuses[CG.Status.BLEED] = 999
	target.status_magnitude[CG.Status.BLEED] = 2.0

	_run(state, _real_deps(), 5)

	var found := 0
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE and e.status == CG.Status.BLEED:
			found += 1
			assert_eq(e.amount, 2, "two stacks, two damage")
			assert_eq(e.damage_type, CG.DamageType.PHYSICAL, "bleeding is physical")
			assert_eq(e.target_id, 1)
	assert_eq(found, 1, "exactly one bleed tick in five, and it is visible")

# ---------------------------------------------------------------------------
# and nothing else moved
# ---------------------------------------------------------------------------

## The placeholder is BLEED-only. BURN and POISON must return exactly what they
## returned before, because both are reachable from content and either would
## move every fight in the game through the shared rng.
func test_the_seams_touch_no_status_that_stores_nothing() -> void:
	var deps := SimDeps.new()
	var unit := _unit(0, CG.Team.PLAYER, 100, Vector2.ZERO)
	for status in [CG.Status.POISON, CG.Status.STUN, CG.Status.SLOWED,
			CG.Status.MARKED, CG.Status.TAUNTING, CG.Status.SHIELDING, CG.Status.HASTE]:
		assert_almost_eq(float(deps.status_damage_per_magnitude.call(unit, status)), 0.0,
			0.0001, "no magnitude damage for %d" % status)
		assert_eq(int(deps.status_tick_interval.call(status)), 1, "still every tick for %d" % status)
		assert_eq(int(deps.status_stack_decay_ticks.call(status)), 0, "no decay window for %d" % status)

## And the two that DO store something carry a live rate. Asserted here rather
## than left implicit, because "BURN is not in the list above" and "BURN is
## wired" are different claims and only the second one is the feature.
func test_burn_and_bleed_both_carry_a_live_magnitude_rate() -> void:
	var deps := SimDeps.new()
	var unit := _unit(0, CG.Team.PLAYER, 100, Vector2.ZERO)
	for status in [CG.Status.BURN, CG.Status.BLEED]:
		assert_true(float(deps.status_damage_per_magnitude.call(unit, status)) > 0.0,
			"status %d stores a magnitude and must be paid for it" % status)

## **INVERTED ON #121, and this is the tripwire doing its job.** It used to
## assert a stored burn magnitude paid nothing -- true while BURN's number sat on
## the base side, and the message said so by name. finch moved it, this fired,
## and the real assertion is the opposite one: the player's ruling is that burn
## damage per tick is relative to the hit that applied it.
func test_a_burn_from_a_bigger_hit_ticks_harder() -> void:
	var plain := _arena()
	plain.unit(1).statuses[CG.Status.BURN] = 999

	var loaded := _arena()
	loaded.unit(1).statuses[CG.Status.BURN] = 999
	loaded.unit(1).status_magnitude[CG.Status.BURN] = 40.0

	_run(plain, _real_deps(), 20)
	_run(loaded, _real_deps(), 20)

	assert_true(loaded.unit(1).hp < plain.unit(1).hp,
		"a burn that remembers a 40-damage hit must hurt more than one that remembers nothing")

## **`test_no_authored_action_applies_bleed_yet` fired on #130 and is gone.**
##
## It asserted that nothing applied BLEED, and said in its own message that the
## day it failed was the day to re-measure. `rat_bite` is what failed it. The
## re-measurement is in that pull request; the assertion is deleted rather than
## loosened, because it was a statement about a moment and the moment passed.

func test_two_runs_from_one_seed_bleed_identically() -> void:
	var a := _arena()
	var b := _arena()
	for s in [a, b]:
		s.unit(1).statuses[CG.Status.BLEED] = 60
		s.unit(1).status_magnitude[CG.Status.BLEED] = 3.0
	_run(a, _real_deps(), 120)
	_run(b, _real_deps(), 120)
	assert_eq(a.unit(1).hp, b.unit(1).hp, "same seed, same bleed")
	assert_eq(a.events.size(), b.events.size(), "and the same event stream")
