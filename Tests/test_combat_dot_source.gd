extends "res://Tests/TestCase.gd"


## #401: a damage-over-time tick names the unit that applied the status.

const _SEED := 4010

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

## Two attackers and one victim, so "which of them applied it" is a question the
## fixture can actually ask. Nothing decides anything: intents are placed by hand.
func _arena(victim_hp: int = 200) -> CombatState:
	var state := CombatState.new(_SEED)
	state.units.append(_unit(0, CG.Team.PLAYER, 200, Vector2.ZERO))
	state.units.append(_unit(1, CG.Team.ENEMY, victim_hp, Vector2(1.0, 0.0)))
	state.units.append(_unit(2, CG.Team.PLAYER, 200, Vector2(2.0, 0.0)))
	return state

func _hit(id: StringName, status: CG.Status, duration: int) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 0
	a.recover_ticks = 0
	a.range_units = 999.0
	a.damage_type = CG.DamageType.PHYSICAL
	a.power_scale = 1.0
	a.applies_status = status
	a.applies_status_enabled = true
	a.status_duration_ticks = duration
	return a

func _deps(actions: Array, dot_rate: float = 3.0) -> SimDeps:
	var by_id := {}
	for a in actions:
		by_id[a.id] = a
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return by_id.get(id)
	deps.attack_power = func(_u: CombatUnit, a: ActionDef, _r = null) -> float: return 10.0 * a.power_scale
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.resource_regen_per_tick = func(_u: CombatUnit) -> float: return 0.0
	## Whole numbers, so `_stochastic_round` never reaches the rng and every
	## assertion below is about attribution rather than about a roll.
	deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return dot_rate
	deps.status_damage_per_magnitude = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.0
	deps.status_tick_interval = func(_s: CG.Status) -> int: return 1
	deps.status_stack_decay_ticks = func(_s: CG.Status) -> int: return 0
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	deps.plan_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return null
	return deps

func _strike(state: CombatState, deps: SimDeps, action: ActionDef, caster: int) -> void:
	state.unit(caster).intent = Intent.use_action(action.id, 1)
	CombatSim.step(state, deps)

## Every DAMAGE event carrying `status`, which is exactly the DOT ticks.
func _dot_ticks(state: CombatState, status: CG.Status) -> Array[CombatEvent]:
	var out: Array[CombatEvent] = []
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE and e.status == status and e.action_id == &"":
			out.append(e)
	return out

func _sources(state: CombatState, status: CG.Status) -> Array[int]:
	var out: Array[int] = []
	for e in _dot_ticks(state, status):
		out.append(e.source_id)
	return out

# ---------------------------------------------------------------------------
# the defect: three statuses, three anonymous channels
# ---------------------------------------------------------------------------

func test_a_poison_tick_names_the_unit_that_applied_it() -> void:
	var jab := _hit(&"jab", CG.Status.POISON, 999)
	var state := _arena()
	var deps := _deps([jab])

	_strike(state, deps, jab, 0)
	for _i in 4:
		CombatSim.step(state, deps)

	var sources := _sources(state, CG.Status.POISON)
	assert_eq(sources.size(), 5, "five ticks of poison")
	for s in sources:
		assert_eq(s, 0, "every one of them names the caster, not -1")

func test_a_burn_tick_names_the_unit_that_applied_it() -> void:
	var scald := _hit(&"scald", CG.Status.BURN, 999)
	var state := _arena()
	var deps := _deps([scald])

	_strike(state, deps, scald, 2)
	CombatSim.step(state, deps)

	assert_eq(_sources(state, CG.Status.BURN), [2, 2] as Array[int], "unit 2 lit it")

func test_a_bleed_tick_names_the_unit_that_applied_it() -> void:
	var cut := _hit(&"cut", CG.Status.BLEED, 999)
	var state := _arena()
	var deps := _deps([cut])

	_strike(state, deps, cut, 0)
	CombatSim.step(state, deps)

	assert_eq(_sources(state, CG.Status.BLEED), [0, 0] as Array[int])

## The playtester's question, and the one the issue was filed for.
func test_a_pawn_killed_by_poison_knows_what_killed_it() -> void:
	var jab := _hit(&"jab", CG.Status.POISON, 999)
	var state := _arena(13) # 10 from the hit, then poison finishes it
	var deps := _deps([jab])

	_strike(state, deps, jab, 0)
	for _i in 4:
		CombatSim.step(state, deps)

	assert_false(state.unit(1).alive, "the poison killed it")
	var death: CombatEvent = null
	for e in state.events:
		if e.kind == CG.EventKind.DEATH:
			death = e
	assert_not_null(death)
	assert_eq(death.source_id, 0, "and the death names the poisoner")

# ---------------------------------------------------------------------------
# the ruling the old `-1` was defending, taken the other way
# ---------------------------------------------------------------------------

## `-1` was chosen because the applier may be dead. It stays named: presentation
## decides what to say about a dead source, the event only has to carry the id.
func test_a_dead_casters_poison_still_names_the_dead_caster() -> void:
	var jab := _hit(&"jab", CG.Status.POISON, 999)
	var state := _arena()
	var deps := _deps([jab])

	_strike(state, deps, jab, 0)
	var caster := state.unit(0)
	caster.hp = 0
	caster.alive = false
	var before := _dot_ticks(state, CG.Status.POISON).size()
	for _i in 3:
		CombatSim.step(state, deps)

	var after := _sources(state, CG.Status.POISON)
	assert_true(after.size() > before, "the poison kept ticking after its caster died")
	for s in after:
		assert_eq(s, 0, "and kept naming them")

# ---------------------------------------------------------------------------
# the negative: what genuinely has no source keeps none
# ---------------------------------------------------------------------------

## A burn lit by a fire pit is nobody's. If this ever reads 0 the field is being
## written where there is no unit to write.
func test_a_hazard_lit_burn_stays_anonymous() -> void:
	var pit = Terrain.hazard(Rect2(-50.0, -50.0, 100.0, 100.0), 0, CG.DamageType.FIRE)
	pit.applies_status = CG.Status.BURN
	pit.applies_status_enabled = true
	pit.status_duration_ticks = 20

	var state := _arena()
	state.terrain = [pit]
	var deps := _deps([])
	for _i in 3:
		CombatSim.step(state, deps)

	var sources := _sources(state, CG.Status.BURN)
	assert_true(sources.size() > 0, "the pit is burning somebody")
	for s in sources:
		assert_eq(s, -1, "terrain has no unit id and must not borrow one")

## A pit refreshing a burn somebody else lit leaves the burn theirs, the same
## way `maxf` leaves its magnitude theirs.
func test_a_pit_does_not_steal_a_burn_a_pawn_lit() -> void:
	var scald := _hit(&"scald", CG.Status.BURN, 999)
	var pit = Terrain.hazard(Rect2(-50.0, -50.0, 100.0, 100.0), 0, CG.DamageType.FIRE)
	pit.applies_status = CG.Status.BURN
	pit.applies_status_enabled = true
	pit.status_duration_ticks = 20

	var state := _arena()
	state.terrain = [pit]
	var deps := _deps([scald])
	_strike(state, deps, scald, 2)
	for _i in 3:
		CombatSim.step(state, deps)

	for s in _sources(state, CG.Status.BURN):
		assert_eq(s, 2, "unit 2 lit it and it stays unit 2's")

# ---------------------------------------------------------------------------
# the field cannot go stale
# ---------------------------------------------------------------------------

func test_a_refresh_re_attributes_the_ticks_that_follow_it() -> void:
	var jab := _hit(&"jab", CG.Status.POISON, 999)
	var state := _arena()
	var deps := _deps([jab])

	_strike(state, deps, jab, 0)
	_strike(state, deps, jab, 2)
	CombatSim.step(state, deps)

	assert_eq(_sources(state, CG.Status.POISON), [0, 2, 2] as Array[int],
		"the first tick is unit 0's, then unit 2 re-applied it")

func test_removing_a_status_takes_its_source_with_it() -> void:
	var jab := _hit(&"jab", CG.Status.POISON, 2)
	var state := _arena()
	var deps := _deps([jab])

	_strike(state, deps, jab, 0)
	var victim := state.unit(1)
	assert_eq(int(victim.status_source.get(CG.Status.POISON, -1)), 0)

	for _i in 3:
		CombatSim.step(state, deps)
	assert_false(victim.has_status(CG.Status.POISON), "expired")
	assert_false(victim.status_source.has(CG.Status.POISON), "and left no phantom applier")

func test_a_cleanse_takes_the_source_too() -> void:
	var jab := _hit(&"jab", CG.Status.POISON, 999)
	var cleanse := ActionDef.new()
	cleanse.id = &"cleanse"
	cleanse.range_units = 999.0
	cleanse.heals = true
	cleanse.cleanses_harmful = true

	var state := _arena()
	var deps := _deps([jab, cleanse])
	_strike(state, deps, jab, 0)

	state.unit(2).intent = Intent.use_action(cleanse.id, 1)
	CombatSim.step(state, deps)
	assert_false(state.unit(1).status_source.has(CG.Status.POISON), "cleansed away with the status")

# ---------------------------------------------------------------------------
# determinism
# ---------------------------------------------------------------------------

## `status_source` is read by key and never iterated, so unlike `statuses` it
## adds no insertion order for two runs from one seed to diverge on.
func test_two_runs_from_one_seed_produce_the_same_sources() -> void:
	var jab := _hit(&"jab", CG.Status.POISON, 30)
	var cut := _hit(&"cut", CG.Status.BLEED, 30)

	var play := func() -> CombatState:
		var state := _arena()
		var deps := _deps([jab, cut], 2.5) # fractional, so `_stochastic_round` draws
		_strike(state, deps, jab, 0)
		_strike(state, deps, cut, 2)
		for _i in 40:
			CombatSim.step(state, deps)
		return state

	var a: CombatState = play.call()
	var b: CombatState = play.call()
	assert_eq(a.events.size(), b.events.size(), "same event stream")
	assert_eq(_sources(a, CG.Status.POISON), _sources(b, CG.Status.POISON))
	assert_eq(_sources(a, CG.Status.BLEED), _sources(b, CG.Status.BLEED))
	assert_eq(a.unit(1).hp, b.unit(1).hp, "and the same fight")

## Carrying an id consumes nothing: the rng stream is where a change here would
## silently move every fight in the game.
func test_naming_the_source_draws_nothing_from_the_rng() -> void:
	var jab := _hit(&"jab", CG.Status.POISON, 999)
	var state := _arena()
	var deps := _deps([jab], 3.0)

	_strike(state, deps, jab, 0)
	for _i in 20:
		CombatSim.step(state, deps)

	var fresh := RandomNumberGenerator.new()
	fresh.seed = _SEED
	assert_eq(state.rng.randf(), fresh.randf(),
		"whole-number rates reach no roll, and attribution reaches none either")
