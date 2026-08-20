extends "res://Tests/TestCase.gd"


## #58, #121 and #132: a taunted unit is FORCED to move into range and use its
## default attack on whoever taunted it.
##
## The test that carries the whole issue is
## `test_a_compelled_pawn_abandons_a_plan_that_says_otherwise`. Taunt already
## influenced targeting inside `DefaultBehavior`, which never runs when a plan
## fired -- and every player pawn has a plan, so the ability was decorative in
## the one situation it exists for. A fixture whose pawn has no plan would pass
## on the old build and prove nothing.
##
## The negative pair matters as much: `test_an_untaunted_unit_decides_for_itself`
## and `test_a_second_taunter_cannot_steal_a_pawn_already_compelled`. A
## compulsion that fires when it should not is worse than one that never fires,
## because it takes the game away from the player rather than merely failing to.

const _SEED := 7200
const _TAUNT_RADIUS := 300.0
const _TAUNT_TICKS := 40

func _unit(id: int, team: CG.Team, pos: Vector2, actions: Array[StringName]) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = 500
	u.hp = 500
	u.resource_max = 100
	u.resource = 100
	u.position = pos
	u.move_speed = 8.0
	u.actions = actions
	return u

func _strike(id: StringName, range_units: float) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 0
	a.recover_ticks = 0
	a.range_units = range_units
	a.damage_type = CG.DamageType.PHYSICAL
	return a

func _taunt(id: StringName) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 0
	a.recover_ticks = 0
	a.range_units = 0.0 # self-targeted, exactly as warrior_taunt is authored
	a.damage_type = CG.DamageType.PHYSICAL
	a.power_scale = 0.0
	a.applies_status = CG.Status.TAUNTING
	a.applies_status_enabled = true
	a.status_duration_ticks = _TAUNT_TICKS
	a.taunt_radius = _TAUNT_RADIUS
	return a

func _deps(actions: Array) -> SimDeps:
	var by_id := {}
	for a in actions:
		by_id[a.id] = a
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return by_id.get(id)
	## Respects power_scale, so the taunt (power_scale 0.0, exactly as
	## warrior_taunt is authored) deals nothing to the caster it is aimed at.
	## Ignoring it made the roar hit its own taunter for 1.
	deps.attack_power = func(_u: CombatUnit, a: ActionDef, _r = null) -> float: return 1.0 * a.power_scale
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.resource_regen_per_tick = func(_u: CombatUnit) -> float: return 0.0
	deps.plan_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return null
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return deps

func _count(state: CombatState, kind: CG.EventKind) -> int:
	var n := 0
	for e in state.events:
		if e.kind == kind:
			n += 1
	return n

## Taunter (unit 0, PLAYER) at the origin. Two enemies: unit 1 close by, unit 2
## far away but still inside the taunt radius. Unit 3 is a PLAYER ally the
## enemies would otherwise prefer, standing right on top of unit 1 so distance
## cannot be what decides the target.
func _arena(taunt: ActionDef) -> CombatState:
	var state := CombatState.new(_SEED)
	state.units.append(_unit(0, CG.Team.PLAYER, Vector2.ZERO, [taunt.id]))
	state.units.append(_unit(1, CG.Team.ENEMY, Vector2(200.0, 0.0), [&"claw"]))
	state.units.append(_unit(2, CG.Team.ENEMY, Vector2(250.0, 0.0), [&"claw"]))
	state.units.append(_unit(3, CG.Team.PLAYER, Vector2(205.0, 0.0), [&"claw"]))
	return state

func _roar(state: CombatState, deps: SimDeps, taunt: ActionDef) -> void:
	var taunter := state.unit(0)
	taunter.focus_id = taunter.id # self-targeted, the way PresetPlans aims it
	taunter.intent = Intent.use_action(taunt.id, taunter.id)
	CombatSim.step(state, deps)

# ---------------------------------------------------------------------------
# it compels
# ---------------------------------------------------------------------------

func test_a_taunt_puts_TAUNTED_on_everyone_it_reaches() -> void:
	var taunt := _taunt(&"roar")
	var state := _arena(taunt)
	_roar(state, _deps([taunt, _strike(&"claw", 40.0)]), taunt)

	assert_true(state.unit(1).has_status(CG.Status.TAUNTED), "the near enemy is compelled")
	assert_true(state.unit(2).has_status(CG.Status.TAUNTED), "so is the far one, inside the radius")
	assert_false(state.unit(3).has_status(CG.Status.TAUNTED), "an ally is not taunted by its own side")
	assert_eq(state.unit(1).status_magnitude.get(CG.Status.TAUNTED, -1.0), 0.0,
		"and the status remembers WHO taunted it")

func test_a_taunt_does_not_reach_past_its_radius() -> void:
	var taunt := _taunt(&"roar")
	var state := _arena(taunt)
	state.unit(2).position = Vector2(_TAUNT_RADIUS + 50.0, 0.0)
	_roar(state, _deps([taunt, _strike(&"claw", 40.0)]), taunt)

	assert_true(state.unit(1).has_status(CG.Status.TAUNTED), "inside")
	assert_false(state.unit(2).has_status(CG.Status.TAUNTED), "outside")

## Forced to MOVE INTO RANGE: a compelled unit walks at the taunter even though
## a closer enemy is standing next to it.
func test_a_compelled_unit_walks_at_the_taunter_past_a_nearer_target() -> void:
	var taunt := _taunt(&"roar")
	var claw := _strike(&"claw", 40.0)
	var state := _arena(taunt)
	var deps := _deps([taunt, claw])
	_roar(state, deps, taunt)

	var enemy := state.unit(1)
	var before := enemy.position.x
	for _i in 5:
		CombatSim.step(state, deps)
	assert_true(enemy.position.x < before, "it closed on the taunter at the origin")
	assert_eq(state.unit(3).hp, 500, "and never touched the ally it was standing beside")

## Forced to USE ITS DEFAULT ATTACK on the taunter once in range.
func test_a_compelled_unit_attacks_the_taunter_once_in_range() -> void:
	var taunt := _taunt(&"roar")
	var claw := _strike(&"claw", 40.0)
	var state := _arena(taunt)
	state.unit(1).position = Vector2(20.0, 0.0) # already in range of the taunter
	var deps := _deps([taunt, claw])
	_roar(state, deps, taunt)
	CombatSim.step(state, deps)

	assert_eq(state.unit(0).hp, 499, "the taunter took the hit")
	assert_eq(state.unit(3).hp, 500, "the ally did not")

## THE TEST THAT CARRIES THE ISSUE. Under the previous rule the compulsion lived
## in `DefaultBehavior`, which never runs when a plan fired -- so a pawn with a
## plan ignored every taunt in the game, which is every player pawn.
func test_a_compelled_pawn_abandons_a_plan_that_says_otherwise() -> void:
	var taunt := _taunt(&"roar")
	var claw := _strike(&"claw", 40.0)
	var state := _arena(taunt)
	state.unit(1).position = Vector2(20.0, 0.0)
	var deps := _deps([taunt, claw])
	## A plan that insists on hitting unit 3 forever. It fires on every tick, so
	## nothing here ever falls through to `default_decide`.
	deps.plan_decide = func(_s: CombatState, u: CombatUnit) -> Intent:
		if u.id == 1:
			return Intent.use_action(claw.id, 3)
		return null
	## The pawn flag is what makes `_decide_phase` consult a plan at all.
	state.unit(1).pawn = state.unit(0).pawn

	_roar(state, deps, taunt)
	for _i in 3:
		CombatSim.step(state, deps)

	assert_true(state.unit(0).hp < 500, "the compulsion beat the plan")
	assert_eq(state.unit(3).hp, 500, "and the plan's own target was never hit")

# ---------------------------------------------------------------------------
# the counters the player asked for
# ---------------------------------------------------------------------------

## Cleansing is the counter, per the player, which is why TAUNTED is harmful and
## why the taunt is a one-shot broadcast rather than a membership test re-run
## every tick -- the latter would overwrite the cleanse on the following tick.
func test_a_cleanse_frees_a_compelled_unit() -> void:
	var taunt := _taunt(&"roar")
	var claw := _strike(&"claw", 40.0)
	var cleanse := ActionDef.new()
	cleanse.id = &"cleanse"
	cleanse.range_units = 999.0
	cleanse.heals = true
	cleanse.cleanses_harmful = true

	var state := _arena(taunt)
	state.unit(1).position = Vector2(20.0, 0.0)
	var deps := _deps([taunt, claw, cleanse])
	_roar(state, deps, taunt)
	assert_true(CG.is_harmful(CG.Status.TAUNTED), "TAUNTED must be cleansable at all")

	# unit 2 is on the taunted unit's own side and cleanses it.
	state.unit(2).intent = Intent.use_action(cleanse.id, 1)
	state.unit(2).focus_id = 1
	CombatSim.step(state, deps)

	var freed := state.unit(1)
	assert_false(freed.has_status(CG.Status.TAUNTED), "cleansed")
	assert_eq(freed.status_magnitude.has(CG.Status.TAUNTED), false, "and it forgot its taunter")

	var hp_before := state.unit(0).hp
	for _i in 3:
		CombatSim.step(state, deps)
	assert_eq(state.unit(0).hp, hp_before, "and it is no longer compelled to attack the taunter")

## It must not permanently lock a pawn. The compulsion carries the roar's own
## advertised duration and then ends on its own.
func test_the_compulsion_expires_on_its_own() -> void:
	var taunt := _taunt(&"roar")
	var claw := _strike(&"claw", 40.0)
	var state := _arena(taunt)
	var deps := _deps([taunt, claw])
	_roar(state, deps, taunt)

	for _i in _TAUNT_TICKS + 2:
		CombatSim.step(state, deps)

	assert_false(state.unit(1).has_status(CG.Status.TAUNTED), "no permanent lock")
	assert_eq(state.unit(1).status_magnitude.has(CG.Status.TAUNTED), false, "and no stale taunter id")

## Killing the taunter is the other counter, and a player who cannot see it
## worked has not been given it.
func test_killing_the_taunter_frees_its_victims_and_says_so() -> void:
	var taunt := _taunt(&"roar")
	var claw := _strike(&"claw", 40.0)
	var state := _arena(taunt)
	var deps := _deps([taunt, claw])
	_roar(state, deps, taunt)
	assert_true(state.unit(1).has_status(CG.Status.TAUNTED))

	state.unit(0).alive = false
	CombatSim.step(state, deps)

	var freed := state.unit(1)
	assert_false(freed.has_status(CG.Status.TAUNTED), "a dead taunter compels nobody")
	var said := false
	for e in state.events:
		if e.kind == CG.EventKind.STATUS_EXPIRED and e.status == CG.Status.TAUNTED and e.target_id == 1:
			said = true
	assert_true(said, "and the release is in the event stream, not silent")

## Enemies must not double-taunt someone. Enforced as a property of the
## mechanism rather than as cleverness in enemy targeting: two taunters split a
## party instead of both piling onto one pawn.
func test_a_second_taunter_cannot_steal_a_pawn_already_compelled() -> void:
	var taunt := _taunt(&"roar")
	var claw := _strike(&"claw", 40.0)
	var state := _arena(taunt)
	var second := _unit(4, CG.Team.PLAYER, Vector2(10.0, 0.0), [taunt.id])
	state.units.append(second)
	var deps := _deps([taunt, claw])

	_roar(state, deps, taunt)
	assert_eq(state.unit(1).status_magnitude.get(CG.Status.TAUNTED, -1.0), 0.0, "taunted by unit 0")

	second.focus_id = second.id
	second.intent = Intent.use_action(taunt.id, second.id)
	CombatSim.step(state, deps)

	assert_eq(state.unit(1).status_magnitude.get(CG.Status.TAUNTED, -1.0), 0.0,
		"still unit 0's: a second roar cannot steal it")
	assert_eq(_count(state, CG.EventKind.STATUS_APPLIED), 4,
		"two TAUNTING on the taunters, two TAUNTED from the first roar, none from the second")

## But a taunter CAN re-take a pawn whose compulsion has already ended, which is
## what stops the no-double-taunt rule from making the first roar permanent.
func test_a_freed_pawn_can_be_taunted_again() -> void:
	var taunt := _taunt(&"roar")
	var claw := _strike(&"claw", 40.0)
	var state := _arena(taunt)
	var deps := _deps([taunt, claw])
	_roar(state, deps, taunt)
	for _i in _TAUNT_TICKS + 2:
		CombatSim.step(state, deps)
	assert_false(state.unit(1).has_status(CG.Status.TAUNTED))

	_roar(state, deps, taunt)
	assert_true(state.unit(1).has_status(CG.Status.TAUNTED), "taunted again once it was free")

# ---------------------------------------------------------------------------
# the negative half
# ---------------------------------------------------------------------------

## The compulsion must not fire on a unit nobody taunted. A compulsion that
## fires when it should not takes the game away from the player, which is worse
## than one that never fires at all.
func test_an_untaunted_unit_decides_for_itself() -> void:
	var claw := _strike(&"claw", 40.0)
	var state := _arena(_taunt(&"roar"))
	var deps := _deps([claw])
	var asked := {"n": 0}
	deps.default_decide = func(_s: CombatState, u: CombatUnit) -> Intent:
		if u.id == 1:
			asked["n"] += 1
		return Intent.idle()

	for _i in 5:
		CombatSim.step(state, deps)

	assert_eq(asked["n"], 5, "the decision layer was asked on every tick, uninterrupted")
	assert_eq(_count(state, CG.EventKind.STATUS_APPLIED), 0, "and nothing was taunted")

## A taunt action with no radius taunts nobody rather than everybody. Content
## authored wrong should look wrong, not reach the whole arena.
func test_a_taunt_with_no_radius_compels_nobody() -> void:
	var taunt := _taunt(&"roar")
	taunt.taunt_radius = 0.0
	var state := _arena(taunt)
	_roar(state, _deps([taunt, _strike(&"claw", 40.0)]), taunt)

	assert_false(state.unit(1).has_status(CG.Status.TAUNTED))
	assert_true(state.unit(0).has_status(CG.Status.TAUNTING), "though the taunter still carries the status")

## The Siege Engine's spawn-time taunt goes through `_build_enemy_unit`, not
## through an action, so it broadcasts nothing and its behaviour is untouched by
## this change. Pinned because the engine is the one thing in the game already
## relying on TAUNTING, and a silent change to it would show up as a balance
## regression nobody could attribute.
func test_a_spawn_time_taunter_compels_nobody() -> void:
	var state := _arena(_taunt(&"roar"))
	var engine := _unit(4, CG.Team.PLAYER, Vector2(200.0, 0.0), [])
	engine.statuses[CG.Status.TAUNTING] = CG.MAX_TICKS
	engine.taunt_radius = _TAUNT_RADIUS
	state.units.append(engine)

	var deps := _deps([_strike(&"claw", 40.0)])
	for _i in 5:
		CombatSim.step(state, deps)

	assert_false(state.unit(1).has_status(CG.Status.TAUNTED),
		"a spawn taunt is a target preference, not a compulsion")

func test_two_runs_from_one_seed_compel_identically() -> void:
	var taunt := _taunt(&"roar")
	var claw := _strike(&"claw", 40.0)
	var play := func() -> CombatState:
		var state := _arena(taunt)
		var deps := _deps([taunt, claw])
		_roar(state, deps, taunt)
		for _i in 30:
			CombatSim.step(state, deps)
		return state
	var a: CombatState = play.call()
	var b: CombatState = play.call()
	assert_eq(a.unit(0).hp, b.unit(0).hp, "same seed, same compulsion")
	assert_eq(a.events.size(), b.events.size(), "and the same event stream")
