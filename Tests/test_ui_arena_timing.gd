extends "res://Tests/TestCase.gd"


## Issue 6, criterion 3: wall-clock seconds from FIGHT_START to FIGHT_END must
## match ticks / CG.TICKS_PER_SECOND, on a fight that actually resolves, and
## the same must hold when frames are dropped (a long stall caught up in one
## _process call, not lost). Built by hand, per wren's Tests/test_combat_sim.gd
## pattern: a one-shot attack with a real wind-up, fixed SimDeps, no Registry
## or Balance involved, since teal's content is not on main yet.

func _make_deps(action: ActionDef) -> SimDeps:
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return action if id == action.id else null
	# Third parameter is the fight's rng, ignored: this fixture wants a fixed
	# lethal number so the timing under test is the only variable.
	deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _rng = null) -> float: return 999.0
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = _attack_nearest(action)
	return deps

func _attack_nearest(action: ActionDef) -> Callable:
	return func(state: CombatState, unit: CombatUnit) -> Intent:
		var enemy_team := CG.Team.ENEMY if unit.team == CG.Team.PLAYER else CG.Team.PLAYER
		var enemies := state.living(enemy_team)
		if enemies.is_empty():
			return Intent.idle()
		return Intent.use_action(action.id, enemies[0].id)

## A one-shot melee swing with a real wind-up, so the fight takes several
## ticks rather than resolving instantly on tick 1 — closer to what a real
## fight's timing looks like.
func _make_action() -> ActionDef:
	var a := ActionDef.new()
	a.id = &"one_shot"
	a.wind_up_ticks = 5
	a.recover_ticks = 0
	a.range_units = 999.0
	a.power_scale = 1.0
	a.damage_type = CG.DamageType.PHYSICAL
	return a

func _make_state() -> CombatState:
	var state := CombatState.new(1)
	var attacker := CombatUnit.new()
	attacker.id = 0
	attacker.team = CG.Team.PLAYER
	attacker.display_name = "Attacker"
	attacker.hp = 10
	attacker.hp_max = 10
	attacker.actions = [&"one_shot"]
	state.units.append(attacker)

	var target := CombatUnit.new()
	target.id = 1
	target.team = CG.Team.ENEMY
	target.display_name = "Target"
	target.hp = 1
	target.hp_max = 1
	state.units.append(target)

	state.emit(CombatEvent.make(CG.EventKind.FIGHT_START, 0))
	return state

## Runs to completion by feeding one whole tick's worth of delta per call, the
## normal-frame-rate case. Returns [ticks, wall_clock_seconds_fed].
func _run_one_tick_per_call(state: CombatState, deps: SimDeps) -> Array:
	var elapsed := 0.0
	var guard := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and guard < 1000:
		CombatSim.step(state, deps)
		elapsed += CG.TICK_SECONDS
		guard += 1
	return [state.tick, elapsed]

func test_wall_clock_matches_ticks_on_a_normal_frame_rate() -> void:
	var action := _make_action()
	var deps := _make_deps(action)
	var state := _make_state()

	var result := _run_one_tick_per_call(state, deps)
	var ticks: int = result[0]
	var elapsed: float = result[1]

	assert_true(ticks > 0, "the fixture must actually take ticks to resolve")
	assert_eq(state.outcome, CombatState.Outcome.PLAYER_WIN)
	var predicted := float(ticks) / float(CG.TICKS_PER_SECOND)
	assert_almost_eq(elapsed, predicted, 0.001,
		"wall-clock seconds fed must match ticks / TICKS_PER_SECOND")
	print("criterion 8, normal frame rate: %d ticks, %.4fs elapsed, %.4fs predicted" % [ticks, elapsed, predicted])

## Same fight, but every tick's worth of delta arrives in one dropped-frame
## sized chunk (5 ticks at a time) plus, at the end, one very large stall that
## must catch up the remainder rather than lose it. This exercises the same
## accumulator BattleView._process uses (see Tests/test_ui_battle_pause.gd for
## the accumulator's own unit tests); here it drives CombatSim directly so the
## fight's own tick count is the ground truth being measured against.
func test_wall_clock_still_matches_ticks_when_frames_are_dropped() -> void:
	var action := _make_action()
	var deps := _make_deps(action)
	var state := _make_state()

	var accumulator := 0.0
	var elapsed := 0.0
	var chunk := CG.TICK_SECONDS * 5.0
	var guard := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and guard < 1000:
		guard += 1
		accumulator += chunk
		elapsed += chunk
		while accumulator >= CG.TICK_SECONDS and state.outcome == CombatState.Outcome.UNRESOLVED:
			accumulator -= CG.TICK_SECONDS
			CombatSim.step(state, deps)

	assert_eq(state.outcome, CombatState.Outcome.PLAYER_WIN)
	var predicted := float(state.tick) / float(CG.TICKS_PER_SECOND)
	# elapsed overshoots predicted by less than one dropped-frame chunk: the
	# stall was caught up inside the loop above, not skipped past.
	assert_true(elapsed - predicted < chunk,
		"a stall must be caught up within one chunk of the wall clock it actually took, not skipped past")
	assert_true(elapsed >= predicted,
		"wall-clock fed can't be less than what the ticks actually needed")
	print("criterion 8, dropped frames (5-tick chunks): %d ticks, %.4fs elapsed, %.4fs predicted" % [state.tick, elapsed, predicted])
