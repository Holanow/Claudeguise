extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")

## Issue 12, the simulation half: a resolving action with `summons_unit_id`
## set adds a unit to `state.units`, on the caster's team, at or near the
## caster. `CombatSim.build()` used to be the only place `state.units` grew;
## this is the first thing in the project that appends to it mid-fight.

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2, actions: Array[StringName]) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.position = pos
	u.move_speed = 8.0
	u.actions = actions
	return u

## A self-targeted, instant "build" action: wind_up 0 so it fires on the tick
## it commits, range 0 so a caster targeting itself is always in range, no
## damage or heal of its own -- exactly a summon and nothing else.
func _build_action(id: StringName, summons: StringName, wind_up: int = 0) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = wind_up
	a.recover_ticks = 1
	a.range_units = 0.0
	a.power_scale = 0.0
	a.summons_unit_id = summons
	return a

func _engine_def(id: StringName, hp: int) -> EnemyDef:
	var e := EnemyDef.new()
	e.id = id
	e.display_name = "Siege Engine"
	e.hp_max = hp
	e.move_speed = 0.0
	e.actions = []
	return e

func _deps(actions_by_id: Dictionary, enemies_by_id: Dictionary) -> SimDeps:
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.enemy_lookup = func(id: StringName): return enemies_by_id.get(id)
	deps.attack_power = func(_u: CombatUnit, a: ActionDef, _rng = null) -> float: return 10.0 * a.power_scale
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_state: CombatState, _unit: CombatUnit) -> Intent: return Intent.idle()
	return deps

# ---------------------------------------------------------------------------
# a summon appears, on the caster's team, at the caster
# ---------------------------------------------------------------------------

func test_a_resolving_summon_action_adds_a_unit_on_the_casters_team() -> void:
	var build := _build_action(&"build", &"engine")
	var engine_def := _engine_def(&"engine", 5)
	var deps := _deps({build.id: build}, {&"engine": engine_def})

	var state := CombatState.new(1)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2(30, 40), [build.id])
	var dummy_enemy := _unit(1, CG.Team.ENEMY, 10, Vector2(1000, 0), [])
	state.units.append(caster)
	state.units.append(dummy_enemy)

	caster.intent = Intent.use_action(build.id, caster.id)
	assert_eq(state.units.size(), 2, "sanity: nothing summoned before the action resolves")

	CombatSim.step(state, deps)

	assert_eq(state.units.size(), 3, "the build action must append exactly one unit")
	var summon := state.units[2]
	assert_eq(summon.id, 2, "a unit appended here must get id == its index")
	assert_eq(summon.team, CG.Team.PLAYER, "a summon takes the caster's team, not the enemy team")
	assert_eq(summon.position, caster.position, "spawned at the caster")
	assert_eq(summon.hp_max, 5)
	assert_eq(summon.hp, 5)
	assert_true(summon.alive)
	assert_eq(summon.enemy_id, &"engine")

func test_state_unit_finds_the_summon_by_id_after_it_is_appended() -> void:
	var build := _build_action(&"build", &"engine")
	var engine_def := _engine_def(&"engine", 5)
	var deps := _deps({build.id: build}, {&"engine": engine_def})

	var state := CombatState.new(2)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [build.id])
	# A living enemy so the fight is still UNRESOLVED after the summon lands --
	# otherwise step() no-ops from here on and the second step below would
	# prove nothing. Same reasoning as the wind-up test above.
	var dummy_enemy := _unit(1, CG.Team.ENEMY, 10, Vector2(100000, 100000), [])
	state.units.append(caster)
	state.units.append(dummy_enemy)

	caster.intent = Intent.use_action(build.id, caster.id)
	CombatSim.step(state, deps)

	var found := state.unit(2)
	assert_not_null(found, "state.unit(id) must resolve a unit summoned this fight")
	assert_eq(found.enemy_id, &"engine")

	# Ids stay stable across further ticks: the same id keeps pointing at the
	# same unit even once it has taken damage or the fight has moved on.
	found.hp = 3
	CombatSim.step(state, deps)
	assert_eq(state.unit(2).hp, 3, "an id must keep meaning the same unit for the rest of the fight")

# ---------------------------------------------------------------------------
# a wind-up delays the spawn -- "building takes real time" is just ticks
# ---------------------------------------------------------------------------

func test_a_long_wind_up_delays_the_spawn_until_it_completes() -> void:
	var build := _build_action(&"build", &"engine", 5)
	var engine_def := _engine_def(&"engine", 5)
	var deps := _deps({build.id: build}, {&"engine": engine_def})

	var state := CombatState.new(3)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [build.id])
	# A living enemy keeps the fight from resolving PLAYER_WIN on tick one
	# (empty enemy team) -- once outcome != UNRESOLVED, step() no-ops and the
	# wind-up would never finish. Same pattern as _dummy_enemy in
	# test_combat_statuses.gd.
	var dummy_enemy := _unit(1, CG.Team.ENEMY, 10, Vector2(100000, 100000), [])
	state.units.append(caster)
	state.units.append(dummy_enemy)

	caster.intent = Intent.use_action(build.id, caster.id)
	for i in 4:
		CombatSim.step(state, deps) # still winding up
		assert_eq(state.units.size(), 2, "no engine before wind-up completes (tick %d)" % (i + 1))

	CombatSim.step(state, deps) # 5th tick: wind-up completes, fires
	assert_eq(state.units.size(), 3, "the engine appears the tick the wind-up lands")

# ---------------------------------------------------------------------------
# determinism: same seed, same fight, same engines
# ---------------------------------------------------------------------------

func test_determinism_holds_with_summoning_in_play() -> void:
	var build := _build_action(&"build", &"engine")
	var atk := ActionDef.new()
	atk.id = &"atk"
	atk.wind_up_ticks = 1
	atk.recover_ticks = 1
	atk.range_units = 999.0
	var engine_def := _engine_def(&"engine", 6)
	var actions_by_id := {build.id: build, atk.id: atk}
	var enemies_by_id := {&"engine": engine_def}

	var make_deps := func() -> SimDeps:
		var d := _deps(actions_by_id, enemies_by_id)
		d.default_decide = func(s: CombatState, u: CombatUnit) -> Intent:
			if u.team == CG.Team.PLAYER and u.actions.has(build.id) and u.id == 0:
				return Intent.use_action(build.id, u.id)
			if u.actions.has(atk.id):
				var enemy_team := CG.Team.ENEMY if u.team == CG.Team.PLAYER else CG.Team.PLAYER
				var enemies := s.living(enemy_team)
				if enemies.is_empty():
					return Intent.idle()
				return Intent.use_action(atk.id, enemies[0].id)
			return Intent.idle()
		return d

	var make_state := func(seed: int) -> CombatState:
		var s := CombatState.new(seed)
		s.units.append(_unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [build.id]))
		s.units.append(_unit(1, CG.Team.ENEMY, 15, Vector2(50, 0), []))
		return s

	var state_a: CombatState = make_state.call(777)
	var state_b: CombatState = make_state.call(777)
	var deps_a: SimDeps = make_deps.call()
	var deps_b: SimDeps = make_deps.call()

	for i in 15:
		CombatSim.step(state_a, deps_a)
		CombatSim.step(state_b, deps_b)

	assert_eq(state_a.units.size(), state_b.units.size(), "same seed must summon the same number of units")
	assert_true(state_a.units.size() > 2, "sanity: a summon must actually have happened")

	assert_eq(state_a.events.size(), state_b.events.size(), "same seed, same event count")
	for i in state_a.events.size():
		var ea: CombatEvent = state_a.events[i]
		var eb: CombatEvent = state_b.events[i]
		assert_eq(ea.kind, eb.kind, "event %d kind diverged" % i)
		assert_eq(ea.source_id, eb.source_id, "event %d source diverged" % i)
		assert_eq(ea.target_id, eb.target_id, "event %d target diverged" % i)
		assert_eq(ea.amount, eb.amount, "event %d amount diverged" % i)

	for i in state_a.units.size():
		assert_eq(state_a.units[i].team, state_b.units[i].team, "unit %d team diverged" % i)
		assert_eq(state_a.units[i].hp, state_b.units[i].hp, "unit %d hp diverged" % i)
		assert_eq(state_a.units[i].position, state_b.units[i].position, "unit %d position diverged" % i)

# ---------------------------------------------------------------------------
# a summoned unit is a real combatant: it can act, be targeted, and die
# ---------------------------------------------------------------------------

func test_a_summoned_unit_can_fight_and_be_killed() -> void:
	var build := _build_action(&"build", &"engine")
	var strike := ActionDef.new()
	strike.id = &"strike"
	strike.wind_up_ticks = 1
	strike.recover_ticks = 1
	strike.range_units = 999.0
	var engine_def := _engine_def(&"engine", 4)
	engine_def.actions = [strike.id]
	var actions_by_id := {build.id: build, strike.id: strike}
	var deps := _deps(actions_by_id, {&"engine": engine_def})
	deps.attack_power = func(_u: CombatUnit, a: ActionDef, _rng = null) -> float:
		return 20.0 if a.id == strike.id else 0.0

	var state := CombatState.new(4)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [build.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(10, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(build.id, caster.id)
	CombatSim.step(state, deps) # the engine is born this tick

	var engine := state.unit(2)
	assert_not_null(engine)
	assert_true(engine.alive)

	engine.intent = Intent.use_action(strike.id, target.id)
	for i in 2:
		CombatSim.step(state, deps)

	assert_eq(target.hp, target.hp_max - 20, "a summoned unit's attack must land like any other unit's")

	# And it dies like any other unit: no special-cased survival path in
	# CombatSim -- damage that drops it to 0 hp kills it the same way as
	# anything else's DAMAGE resolution does.
	engine.hp = 0
	engine.alive = false
	assert_false(engine.alive, "a summoned unit must be able to die like any other")

# ---------------------------------------------------------------------------
# an unknown summon id fails the same way an unknown enemy spawn already does
# ---------------------------------------------------------------------------

func test_unknown_summon_id_still_appends_a_unit_rather_than_crashing() -> void:
	var build := _build_action(&"build", &"nonexistent_engine")
	var deps := _deps({build.id: build}, {})

	var state := CombatState.new(5)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [build.id])
	state.units.append(caster)

	caster.intent = Intent.use_action(build.id, caster.id)
	CombatSim.step(state, deps)

	assert_eq(state.units.size(), 2, "an unknown id must not silently drop the summon")
	assert_eq(state.units[1].team, CG.Team.PLAYER, "even the fallback unit takes the caster's team")
	assert_eq(state.units[1].hp_max, 1, "same fallback shape build() already uses for an unknown enemy id")
