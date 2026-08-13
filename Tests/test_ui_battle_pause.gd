extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const BattleScene := preload("res://Scenes/Battle.tscn")

## Real time, with a pause: the view accumulates wall-clock delta and spends it
## in whole ticks, so frame rate cannot change fight speed, and pause just
## stops spending the accumulator rather than resetting it.
##
## These tests drive _process() directly with hand-picked deltas instead of
## waiting on real frames, and check the accumulator rather than any effect of
## CombatSim.step, because CombatSim is wren's stub today and does not advance
## state.tick yet. Instantiating the real Battle.tscn (rather than
## BattleView.new()) is required: _ready() looks up the Arena and Hud/CombatLog
## children by name, which only exist once the scene is instantiated.
##
## _ready() is called directly rather than via add_child(), because the test
## runner (Tests/run_tests.gd) is not reachable through Engine.get_main_loop()
## from inside its own _init(). BattleView._ready() is written to tolerate
## this: viewport-dependent layout is skipped when the node has no tree, which
## is exactly the case here.

func _spawn_battle_view():
	var view = BattleScene.instantiate()
	view._ready()
	var config := RunConfig.new()
	config.seed = 1
	view.begin(config)
	return view

func test_a_partial_tick_of_delta_accumulates_without_stepping() -> void:
	var view = _spawn_battle_view()
	var half_tick := CG.TICK_SECONDS * 0.5
	view._process(half_tick)
	assert_almost_eq(view._tick_accumulator, half_tick, 0.0001)
	view.free()

func test_a_full_tick_of_delta_resets_the_accumulator() -> void:
	var view = _spawn_battle_view()
	view._process(CG.TICK_SECONDS * 0.5)
	view._process(CG.TICK_SECONDS * 0.5)
	assert_almost_eq(view._tick_accumulator, 0.0, 0.0001)
	view.free()

func test_a_dropped_frame_catches_up_instead_of_slowing_down() -> void:
	# Several ticks worth of delta arriving in one frame, as a loaded machine
	# would deliver, must not leave a backlog sitting unspent.
	var view = _spawn_battle_view()
	view._process(CG.TICK_SECONDS * 5.5)
	assert_almost_eq(view._tick_accumulator, CG.TICK_SECONDS * 0.5, 0.0001)
	view.free()

func test_pause_stops_the_accumulator_from_advancing() -> void:
	var view = _spawn_battle_view()
	view.set_paused(true)
	view._process(CG.TICK_SECONDS * 3.0)
	assert_almost_eq(view._tick_accumulator, 0.0, 0.0001)
	view.free()

func test_unpause_resumes_from_where_it_was_held_not_from_zero() -> void:
	var view = _spawn_battle_view()
	view._process(CG.TICK_SECONDS * 0.5)
	view.set_paused(true)
	view._process(CG.TICK_SECONDS * 10.0)  # held; must be discarded entirely
	view.set_paused(false)
	view._process(CG.TICK_SECONDS * 0.5)
	# 0.5 tick + 0.5 tick = exactly one tick spent, accumulator back near zero,
	# not the ten ticks' worth that arrived while paused.
	assert_almost_eq(view._tick_accumulator, 0.0, 0.0001)
	view.free()

func test_space_bar_toggles_pause() -> void:
	var view = _spawn_battle_view()
	assert_false(view.paused)
	var press := InputEventKey.new()
	press.keycode = KEY_SPACE
	press.pressed = true
	view._unhandled_input(press)
	assert_true(view.paused)
	view._unhandled_input(press)
	assert_false(view.paused)
	view.free()
