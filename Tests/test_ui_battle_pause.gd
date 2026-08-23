extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Real time, with a pause: the view accumulates wall-clock delta and spends it
## in whole ticks, so frame rate cannot change fight speed, and pause just
## stops spending the accumulator rather than resetting it.

func _make_party() -> Array[PawnData]:
	var cls := ClassDef.new()
	cls.id = &"test_class"
	cls.display_name = "Test Class"
	var pawn := PawnData.new()
	pawn.id = &"test_pawn"
	pawn.display_name = "Test Pawn"
	pawn.pawn_class = cls
	var out: Array[PawnData] = [pawn]
	return out

func _make_encounter() -> Encounter:
	var e := Encounter.new()
	e.enemy_spawns = [{"enemy_id": &"test_dummy", "position": Vector2(80.0, 0.0)}]
	e.party_spawns = [Vector2(-80.0, 0.0)]
	return e

func _spawn_battle_view():
	var view = in_tree(BattleScene.instantiate())
	view._ready()
	var config := RunConfig.new()
	config.seed = 1
	config.party = _make_party()
	view.config = config
	view.state = CombatSim.build(config.party, _make_encounter(), config.seed)
	view.event_cursor = 0
	view._tick_accumulator = 0.0
	view.set_paused(false)
	view._rebuild_units()
	view._party_label.text = "Party: Test Pawn"
	view._seed_label.text = "Seed " + config.seed_text()
	view._outcome_label.text = ""
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

## PLAYTEST-NOTES-2 item 5: "pause needs to be obvious -- grey the screen
## or similar. Nothing currently indicates it."
func test_pause_shows_the_dim_overlay() -> void:
	var view = _spawn_battle_view()
	assert_false(view._pause_dim.visible, "must not be dimmed before pausing")
	view.set_paused(true)
	assert_true(view._pause_dim.visible)
	view.free()

func test_resuming_hides_the_dim_overlay_again() -> void:
	var view = _spawn_battle_view()
	view.set_paused(true)
	view.set_paused(false)
	assert_false(view._pause_dim.visible)
	view.free()

func test_space_bar_also_toggles_the_dim_overlay() -> void:
	var view = _spawn_battle_view()
	var press := InputEventKey.new()
	press.keycode = KEY_SPACE
	press.pressed = true
	view._unhandled_input(press)
	assert_true(view._pause_dim.visible)
	view._unhandled_input(press)
	assert_false(view._pause_dim.visible)
	view.free()

## Issue 18 criterion 3: every control at least TOUCH_TARGET_MIN on its
## short side, asserted rather than eyeballed. Unset, a Button's default
## minimum height comes in under 48 and looks fine in a screenshot anyway.
func test_hud_buttons_meet_the_minimum_touch_target() -> void:
	var view = _spawn_battle_view()
	assert_true(view._pause_button.custom_minimum_size.y >= Palette.TOUCH_TARGET_MIN)
	view.free()

## Issue 43: the toolbar used to hold four labels and three buttons in one
## HBoxContainer, wide enough to run off the screen the moment a label got
## long (the room name, issue 36) or the viewport got narrow. Split into an
## info row and a controls row — this pins that the buttons live in their
## own row, not sharing one with the labels, so a future change can't
## silently merge them back.
func test_controls_are_a_separate_row_from_the_info_labels() -> void:
	var view = _spawn_battle_view()
	assert_ne(view._pause_button.get_parent(), view._party_label.get_parent(),
		"buttons and labels must not share a row, or a long label can push a button off-screen")
	view.free()
