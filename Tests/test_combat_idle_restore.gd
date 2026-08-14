extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")

## Issue 132: a unit that spends its tick idle recovers resource faster than one
## that spends it moving or fighting. The first thing in this game that trades
## time for resource.
##
## The two tests that matter most here are the negative ones, and they are not
## the obvious pair:
##
##   test_the_default_scale_leaves_an_idle_unit_on_the_ordinary_rate
##   test_the_default_scale_consumes_no_random_number
##
## The second is the one I would not have thought to write from the feature
## description. `_stochastic_round` reads `state.rng`, and the rng stream is
## shared by every damage roll in the fight -- so a mechanism that consumed one
## extra random number per idle tick would silently change the outcome of every
## fight this project has ever measured, while every assertion about resource
## still passed. It is checked directly against a fresh generator on the same
## seed, and `test_a_live_scale_does_consume_a_random_number` proves that check
## is not inert.
##
## Every assertion is an exact number rather than an inequality, per announcement
## rule 4: these fixtures are deterministic, so there is nothing to be gained by
## weakening one to `> 0`.

const _SEED := 4242
const _RESOURCE_MAX := 100

func _unit(id: int, kind: CG.ResourceKind = CG.ResourceKind.MANA) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.PLAYER
	u.hp_max = 100
	u.hp = 100
	u.resource_max = _RESOURCE_MAX
	u.resource = 0
	u.resource_kind = kind
	u.position = Vector2.ZERO
	u.move_speed = 8.0
	return u

## One player unit and one enemy, so `_check_outcome` never resolves the fight
## out from under a multi-tick test. Neither ever attacks: `default_decide`
## below hands out whatever intent the test asked for.
func _arena(kind: CG.ResourceKind = CG.ResourceKind.MANA) -> CombatState:
	var state := CombatState.new(_SEED)
	state.units.append(_unit(0, kind))
	var enemy := _unit(1)
	enemy.team = CG.Team.ENEMY
	enemy.position = Vector2(400.0, 0.0)
	state.units.append(enemy)
	return state

## `base` is deliberately a whole number in most tests: `_stochastic_round`
## reads `state.rng` only for a fractional part, so a whole rate keeps the
## resource assertions exact and keeps the rng question in the one pair of tests
## written to ask it.
func _deps(base: float, scale: float = -1.0, intent: Intent = null) -> SimDeps:
	var deps := SimDeps.new()
	deps.resource_regen_per_tick = func(_u: CombatUnit) -> float: return base
	if scale >= 0.0:
		deps.idle_resource_regen_scale = func(_u: CombatUnit) -> float: return scale
	var chosen := intent
	deps.default_decide = func(_s: CombatState, u: CombatUnit) -> Intent:
		if u.id != 0:
			return Intent.idle()
		return Intent.idle() if chosen == null else chosen
	return deps

func _run(state: CombatState, deps: SimDeps, ticks: int) -> void:
	for _i in ticks:
		CombatSim.step(state, deps)

# ---------------------------------------------------------------------------
# it restores, and only while idle
# ---------------------------------------------------------------------------

func test_an_idle_unit_recovers_at_the_scaled_rate() -> void:
	var state := _arena()
	# base 2 per tick, tripled while idle: 2 from _tick_regen plus 4 extra.
	_run(state, _deps(2.0, 3.0), 5)
	assert_eq(state.unit(0).resource, 30, "5 ticks x (2 ordinary + 4 idle bonus)")

func test_a_moving_unit_recovers_only_the_ordinary_rate() -> void:
	var state := _arena()
	var deps := _deps(2.0, 3.0, Intent.move_to(Vector2(200.0, 0.0)))
	_run(state, deps, 5)
	var unit := state.unit(0)
	assert_eq(unit.resource, 10, "5 ticks x 2, no idle bonus while walking")
	assert_ne(unit.position, Vector2.ZERO, "and it really did move")

func test_a_unit_using_an_action_recovers_only_the_ordinary_rate() -> void:
	var action := ActionDef.new()
	action.id = &"swing"
	action.wind_up_ticks = 3
	action.recover_ticks = 3
	action.range_units = 999.0
	var state := _arena()
	var deps := _deps(2.0, 3.0, Intent.use_action(action.id, 1))
	deps.action_lookup = func(id: StringName): return action if id == action.id else null
	deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _r = null) -> float: return 0.0
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	_run(state, deps, 5)
	var unit := state.unit(0)
	assert_eq(unit.resource, 10, "5 ticks x 2: committing, winding up and recovering are not idling")
	assert_eq(unit.current_action, action.id, "and it really was busy with the action")

## A stunned unit is not offered an intent at all, so it never reaches the IDLE
## branch. Worth pinning: "standing there doing nothing" and "being unable to
## act" look identical on screen and must not pay the same.
func test_a_stunned_unit_gets_no_idle_bonus() -> void:
	var state := _arena()
	state.unit(0).statuses[CG.Status.STUN] = 999
	_run(state, _deps(2.0, 3.0), 5)
	assert_eq(state.unit(0).resource, 10, "5 ticks x 2, no bonus while stunned")

# ---------------------------------------------------------------------------
# rage, and the ceiling
# ---------------------------------------------------------------------------

## `_tick_regen` already refuses to regenerate Rage. `_resolve_idle` refuses
## separately rather than relying on the rate function returning zero, so a
## content mistake cannot make a berserker fill up by standing still.
func test_an_idle_rage_unit_recovers_nothing() -> void:
	var state := _arena(CG.ResourceKind.RAGE)
	_run(state, _deps(2.0, 10.0), 5)
	assert_eq(state.unit(0).resource, 0, "rage is earned by landing hits, never by waiting")

func test_the_idle_bonus_stops_at_the_ceiling() -> void:
	var state := _arena()
	state.unit(0).resource = _RESOURCE_MAX - 1
	_run(state, _deps(2.0, 50.0), 5)
	assert_eq(state.unit(0).resource, _RESOURCE_MAX, "clamped, never over")

# ---------------------------------------------------------------------------
# the negative half: with nobody wiring a number, nothing at all changed
# ---------------------------------------------------------------------------

func test_the_default_scale_leaves_an_idle_unit_on_the_ordinary_rate() -> void:
	var state := _arena()
	_run(state, _deps(2.0), 5)
	assert_eq(state.unit(0).resource, 10, "5 ticks x 2 and not one point more")

## The check the resource assertions cannot make. `state.rng` is shared with
## every damage roll in the fight, so one extra draw per idle tick would move
## every fight in the game while every number above still read correctly.
func test_the_default_scale_consumes_no_random_number() -> void:
	var state := _arena()
	_run(state, _deps(0.0), 20)
	var fresh := RandomNumberGenerator.new()
	fresh.seed = _SEED
	assert_eq(state.rng.randf(), fresh.randf(), "20 idle ticks drew nothing from the fight's rng")

## And the proof that the check above is capable of failing. Same base rate in
## both fights, so `_tick_regen` draws identically in each and the ONLY
## difference is the idle bonus: a live scale reaches `_stochastic_round` on a
## fractional amount, and the two rng streams come apart.
func test_a_live_scale_does_consume_a_random_number() -> void:
	var inert := _arena()
	var live := _arena()
	_run(inert, _deps(0.5, 1.0), 20)
	_run(live, _deps(0.5, 2.0), 20)
	assert_ne(live.rng.randf(), inert.rng.randf(), "a live scale draws, so the test above is not inert")

## Not "no authored action uses it" -- there is no action to author. The seam
## itself is the thing that has to be unwired, and this is what will fail on the
## day content points it at a real number, which is exactly when the balance
## table needs re-measuring.
func test_no_content_has_wired_the_idle_scale_yet() -> void:
	var deps := SimDeps.new()
	var unit := _unit(0)
	assert_almost_eq(float(deps.idle_resource_regen_scale.call(unit)), 1.0,
		0.0001, "SimDeps default is still 1.0: idling pays nothing extra in a real fight")

# ---------------------------------------------------------------------------
# determinism
# ---------------------------------------------------------------------------

func test_two_runs_from_one_seed_restore_identically() -> void:
	var a := _arena()
	var b := _arena()
	_run(a, _deps(0.5, 3.0), 40)
	_run(b, _deps(0.5, 3.0), 40)
	assert_eq(a.unit(0).resource, b.unit(0).resource, "same seed, same restore")
	assert_eq(a.events.size(), b.events.size(), "and the same event stream")
