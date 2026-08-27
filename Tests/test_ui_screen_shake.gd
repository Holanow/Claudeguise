extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 518: the arena kicks and settles on a death, scaled to what died, and
## off unless the player asks for it.

## Built from the registry's own enemy, radius and all: the amplitude is scaled
## off the DRAWN body, so a hand-typed radius would measure a body nothing has.
func _unit(id: int, team: CG.Team, at: Vector2, shape: StringName) -> CombatUnit:
	var def := EnemyLibrary.get_enemy(shape)
	assert_true(def != null, "the fixture needs enemy %s to still exist" % shape)
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.display_name = "u%d" % id
	u.position = at
	u.hp = 10
	u.hp_max = 10
	u.enemy_id = shape
	u.radius = def.radius
	return u

## A rat and the Rat King, which are the two ends of the drawn-body range.
func _view_with_pair() -> Node2D:
	var state := CombatState.new(1)
	state.units.append(_unit(0, CG.Team.ENEMY, Vector2.ZERO, &"rat"))
	state.units.append(_unit(1, CG.Team.ENEMY, Vector2(60.0, 0.0), &"rat_king"))
	var view = in_tree(BattleScene.instantiate())
	view.state = state
	view.event_cursor = 0
	view._rebuild_units()
	view._arena_base = view._arena.position
	return view

func _death(id: int) -> CombatEvent:
	var e := CombatEvent.make(CG.EventKind.DEATH, 1)
	e.source_id = -1
	e.target_id = id
	return e

# --- the shape of the settle ------------------------------------------------

func test_the_kick_is_furthest_at_the_moment_of_the_death() -> void:
	var at_death := BattleView.shake_offset(0.0, 10.0)
	assert_almost_eq(at_death.x, 10.0)
	assert_almost_eq(at_death.y, 0.0)

## Not "near zero". The arena has to land back on the pixel `_layout_arena` put
## it on, or every fight ends a fraction of a pixel off where it started.
func test_the_arena_lands_back_on_exactly_its_layout_position() -> void:
	assert_eq(BattleView.shake_offset(BattleView.SHAKE_SECONDS, 10.0), Vector2.ZERO)
	assert_eq(BattleView.shake_offset(99.0, 10.0), Vector2.ZERO)
	assert_eq(BattleView.shake_offset(INF, 10.0), Vector2.ZERO)
	assert_eq(BattleView.shake_offset(0.0, 0.0), Vector2.ZERO)

## A shake is an oscillation, not a lurch: it has to cross its rest position
## rather than travel one way and ease home.
func test_it_crosses_its_rest_position_rather_than_easing_one_way() -> void:
	var crossings := 0
	var last := BattleView.shake_offset(0.0, 10.0).x
	for i in range(1, 60):
		var x := BattleView.shake_offset(BattleView.SHAKE_SECONDS * float(i) / 60.0, 10.0).x
		if signf(x) != signf(last) and x != 0.0:
			crossings += 1
		last = x
	assert_true(crossings >= 2, "expected the arena to cross rest at least twice, got %d" % crossings)

func test_the_amplitude_decays_rather_than_holding() -> void:
	var early := BattleView.shake_offset(BattleView.SHAKE_SECONDS * 0.05, 10.0).length()
	var late := BattleView.shake_offset(BattleView.SHAKE_SECONDS * 0.9, 10.0).length()
	assert_true(late < early * 0.2, "%.3f px late against %.3f px early" % [late, early])

# --- what a death does ------------------------------------------------------

func test_a_death_moves_the_arena_and_then_puts_it_back() -> void:
	DisplayOptions.set_enabled(&"screen_shake", true)
	var view := _view_with_pair()
	var base: Vector2 = view._arena_base
	view.state.emit(_death(1))
	view.consume_events()
	view._advance_shake(0.0)
	assert_ne(view._arena.position, base, "the arena should have kicked")

	for i in 30:
		view._advance_shake(1.0 / 60.0)
	assert_eq(view._arena.position, base, "and settled back on the layout pixel")
	DisplayOptions.reset()

## The issue's own line: a rat dying is not the Warden dying.
func test_a_bigger_body_shakes_the_screen_further() -> void:
	DisplayOptions.set_enabled(&"screen_shake", true)
	var small := _view_with_pair()
	small.state.emit(_death(0))
	small.consume_events()
	var big := _view_with_pair()
	big.state.emit(_death(1))
	big.consume_events()

	assert_true(big._shake_amplitude > small._shake_amplitude * 1.5,
		"rat %.2f px against rat king %.2f px" % [small._shake_amplitude, big._shake_amplitude])
	assert_true(big._shake_amplitude <= BattleView.SHAKE_PIXELS,
		"nothing may shake further than the cap")
	DisplayOptions.reset()

## Three deaths in one tick are one event to the reader, and the biggest of them
## is the one that sets the size.
func test_a_tick_that_kills_two_shakes_once_at_the_bigger_size() -> void:
	DisplayOptions.set_enabled(&"screen_shake", true)
	var view := _view_with_pair()
	view.state.emit(_death(0))
	view.state.emit(_death(1))
	view.consume_events()
	var biggest: float = view._shake_amplitude
	assert_eq(view._shake_age, 0.0, "one shake, started once")

	var other := _view_with_pair()
	other.state.emit(_death(1))
	other.state.emit(_death(0))
	other.consume_events()
	# The order the two deaths arrive in must not change the size.
	assert_almost_eq(other._shake_amplitude, biggest)
	DisplayOptions.reset()

# --- the negative cases -----------------------------------------------------

## The one row in `DisplayOptions` that is off unless the player asks. Every
## measurement behind this issue says the camera is the reading surface.
func test_the_option_is_off_until_the_player_turns_it_on() -> void:
	DisplayOptions.reset()
	assert_false(DisplayOptions.enabled(&"screen_shake"),
		"screen shake must not default on")

func test_the_toggle_off_leaves_the_arena_exactly_where_it_was() -> void:
	DisplayOptions.set_enabled(&"screen_shake", false)
	var view := _view_with_pair()
	var base: Vector2 = view._arena_base
	view.state.emit(_death(1))
	view.consume_events()
	view._advance_shake(1.0 / 60.0)

	assert_eq(view._arena.position, base)
	assert_eq(view._shake_amplitude, 0.0)
	DisplayOptions.reset()

func test_a_hit_that_kills_nobody_never_moves_the_screen() -> void:
	DisplayOptions.set_enabled(&"screen_shake", true)
	var view := _view_with_pair()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = 0
	e.target_id = 1
	e.action_id = &"warrior_strike"
	e.amount = 3
	view.state.emit(e)
	view.consume_events()

	assert_eq(view._arena.position, view._arena_base, "shake is deaths only")
	DisplayOptions.reset()

## Issue 515 freezes the picture by returning out of `_process` before
## `_render`, and the shake is spent from `_render`. A screen still moving
## through a freeze frame is the exact bug #515 and #516 nearly shipped twice.
func test_a_hit_stop_holds_the_shake_with_everything_else() -> void:
	DisplayOptions.set_enabled(&"screen_shake", true)
	DisplayOptions.set_enabled(&"hit_stop", true)
	var view := _view_with_pair()
	view.state.emit(_death(1))
	view.consume_events()
	view._hit_stop()
	view._advance_shake(0.0)
	var held: Vector2 = view._arena.position

	for i in 6:
		view._process(1.0 / 60.0)
	assert_eq(view._arena.position, held, "the arena kept moving during a freeze frame")
	DisplayOptions.reset()

## A resize while a shake is live has to re-anchor it rather than baking the
## offset into the new layout position, or every death nudges the arena
## permanently off centre.
func test_a_relayout_mid_shake_re_anchors_rather_than_banking_the_offset() -> void:
	DisplayOptions.set_enabled(&"screen_shake", true)
	var view := _view_with_pair()
	view.state.emit(_death(1))
	view.consume_events()
	view._advance_shake(0.0)
	view._layout_arena()
	var base: Vector2 = view._arena_base
	for i in 30:
		view._advance_shake(1.0 / 60.0)
	assert_eq(view._arena.position, base)
	DisplayOptions.reset()

# --- the line that must not be crossed --------------------------------------

## View layer only, and no draw from `state.rng`: a probe that touches the
## simulation's stream changes the fight it is watching (#329).
func test_the_shake_never_reaches_the_simulation() -> void:
	DisplayOptions.set_enabled(&"screen_shake", true)
	var view := _view_with_pair()
	var rng_before: int = view.state.rng.state
	var before: Array = []
	for u in view.state.units:
		before.append(u.position)
	view.state.emit(_death(1))
	view.consume_events()
	for i in 4:
		view._advance_shake(1.0 / 60.0)

	assert_eq(view.state.rng.state, rng_before, "the shake drew from the fight's own rng")
	for i in view.state.units.size():
		assert_eq(view.state.units[i].position, before[i], "a shake moved a simulated position")
	DisplayOptions.reset()
