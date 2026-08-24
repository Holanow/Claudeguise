extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 531: #516 recoils a melee attacker off the body it hit, which leaves a
## ranged attacker with no reaction at all. The kick belongs at the loose.

## A projectile action and a melee one, taken from the registry rather than
## invented, so a content change that stops either being what it says here goes
## red instead of quietly measuring nothing.
const SHOT := &"goblin_arrow"
const SWING := &"warrior_strike"

func _unit(id: int, team: CG.Team, at: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.display_name = "u%d" % id
	u.position = at
	u.hp = 10
	u.hp_max = 10
	return u

func _view_with_pair(apart: float = 600.0) -> Node2D:
	var state := CombatState.new(1)
	state.units.append(_unit(0, CG.Team.PLAYER, Vector2.ZERO))
	state.units.append(_unit(1, CG.Team.ENEMY, Vector2(apart, 0.0)))
	var view = in_tree(BattleScene.instantiate())
	view.state = state
	view.event_cursor = 0
	view._rebuild_units()
	return view

func _fire(source: int, target: int, action: StringName) -> CombatEvent:
	var e := CombatEvent.make(CG.EventKind.ACTION_FIRE, 1)
	e.source_id = source
	e.target_id = target
	e.action_id = action
	return e

# --- the fixture says what it claims ----------------------------------------

func test_the_two_action_ids_are_still_what_this_file_assumes() -> void:
	var shot := Registry.get_action(SHOT)
	var swing := Registry.get_action(SWING)
	assert_true(shot != null and shot.projectile_speed > 0.0,
		"%s must still be a projectile action" % SHOT)
	assert_true(swing != null and swing.projectile_speed <= 0.0,
		"%s must still be a melee action" % SWING)

# --- what a loose does ------------------------------------------------------

func test_an_archer_kicks_back_at_the_moment_it_looses() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair()
	view.state.emit(_fire(1, 0, SHOT))
	view.consume_events()

	var shooter: Node2D = view._unit_views[1]
	assert_true(shooter.impact_active(), "the shooter should be recoiling at the loose")
	# Unit 1 stands to the right of unit 0, so it is thrown further right.
	assert_true(shooter._recoil_direction.x > 0.9,
		"the kick points away from the target, got %.2f" % shooter._recoil_direction.x)
	assert_false(view._unit_views[0].impact_active(),
		"nothing has hit the target yet: the arrow is still in the air")
	DisplayOptions.reset()

## The distance gate `_apply_impact` uses exists because a projectile's DAMAGE
## fires at the far end of the arena. At the loose the shooter is where the shot
## starts, so distance must not gate it -- a bow is a ranged weapon.
func test_range_never_gates_the_loose() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	for apart in [20.0, 600.0]:
		var view := _view_with_pair(apart)
		view.state.emit(_fire(1, 0, SHOT))
		view.consume_events()
		assert_true(view._unit_views[1].impact_active(),
			"a loose %.0f units from the target still kicks" % apart)
	DisplayOptions.reset()

## Softer than an impact recoil, and it has to stay softer: a full kick with
## nothing struck reads as the archer being hit rather than as it firing.
func test_the_loose_kicks_less_far_than_a_landed_blow() -> void:
	assert_true(UnitView.LOOSE_PIXELS < UnitView.RECOIL_PIXELS,
		"the loose is %.1f px against a blow's %.1f" % [
			UnitView.LOOSE_PIXELS, UnitView.RECOIL_PIXELS])
	var loose := UnitView.recoil_offset(0.0, Vector2.RIGHT, UnitView.LOOSE_PIXELS)
	assert_almost_eq(loose.x, UnitView.LOOSE_PIXELS)
	assert_eq(UnitView.recoil_offset(UnitView.RECOIL_SECONDS, Vector2.RIGHT,
		UnitView.LOOSE_PIXELS), Vector2.ZERO)

## The two distances share one age and one decay, so whichever fired last is the
## one being drawn. A blow that lands on an archer mid-kick must not be drawn at
## the loose's smaller distance.
func test_a_landed_blow_takes_over_a_kick_already_running() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair(20.0)
	var shooter: Node2D = view._unit_views[1]
	shooter.recoiled(Vector2.RIGHT, UnitView.LOOSE_PIXELS)
	assert_almost_eq(UnitView.recoil_offset(shooter._recoil_age, shooter._recoil_direction,
		shooter._recoil_pixels).x, UnitView.LOOSE_PIXELS)
	shooter.recoiled(Vector2.RIGHT)
	assert_almost_eq(UnitView.recoil_offset(shooter._recoil_age, shooter._recoil_direction,
		shooter._recoil_pixels).x, UnitView.RECOIL_PIXELS)
	DisplayOptions.reset()

# --- the negative cases -----------------------------------------------------

## A melee swing's ACTION_FIRE and its DAMAGE land on the same tick, so reacting
## to both would recoil the same body twice for one blow.
func test_a_melee_swing_is_not_recoiled_at_its_own_fire() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair(20.0)
	view.state.emit(_fire(1, 0, SWING))
	view.consume_events()

	assert_false(view._unit_views[1].impact_active(),
		"the swing recoils when it lands, not when it is thrown")
	assert_false(view._unit_views[0].impact_active())
	DisplayOptions.reset()

func test_a_loose_at_nobody_moves_nothing() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair()
	view.state.emit(_fire(1, -1, SHOT))
	view.consume_events()

	assert_false(view._unit_views[1].impact_active(),
		"there is no direction to kick away from")
	DisplayOptions.reset()

func test_the_toggle_off_leaves_the_shooter_exactly_where_it_was() -> void:
	DisplayOptions.set_enabled(&"impact_squash", false)
	var view := _view_with_pair()
	view.state.emit(_fire(1, 0, SHOT))
	view.consume_events()

	assert_false(view._unit_views[1].impact_active())
	DisplayOptions.reset()

func test_the_kick_ends_and_gives_the_frame_back() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair()
	view.state.emit(_fire(1, 0, SHOT))
	view.consume_events()

	var shooter: Node2D = view._unit_views[1]
	for i in 60:
		shooter.advance_impact(1.0 / 60.0)
	assert_false(shooter.impact_active(), "one second is five spans")
	assert_eq(shooter._recoil_pixels, UnitView.RECOIL_PIXELS,
		"a finished kick leaves the distance back at its default")
	DisplayOptions.reset()

## Issue 515 freezes the picture by returning out of `_process` before
## `_render`, and the kick is spent from `_render`. A kick that keeps travelling
## through a freeze frame is motion in a picture that has stopped.
func test_a_hit_stop_holds_the_kick_with_everything_else() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	DisplayOptions.set_enabled(&"hit_stop", true)
	var view := _view_with_pair()
	view.state.emit(_fire(1, 0, SHOT))
	view.consume_events()
	view._hit_stop()

	var shooter: Node2D = view._unit_views[1]
	var held: Vector2 = UnitView.recoil_offset(shooter._recoil_age,
		shooter._recoil_direction, shooter._recoil_pixels)
	for i in 6:
		view._process(1.0 / 60.0)
	assert_eq(UnitView.recoil_offset(shooter._recoil_age, shooter._recoil_direction,
		shooter._recoil_pixels), held, "the shooter kept travelling during a freeze frame")
	DisplayOptions.reset()

# --- the line that must not be crossed --------------------------------------

func test_the_kick_never_reaches_the_simulation() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair()
	var before: Array = []
	for u in view.state.units:
		before.append([u.position, u.radius])
	view.state.emit(_fire(1, 0, SHOT))
	view.consume_events()
	var shooter: Node2D = view._unit_views[1]
	var at := shooter.position
	for i in 4:
		shooter.advance_impact(1.0 / 60.0)

	for i in view.state.units.size():
		var u: CombatUnit = view.state.units[i]
		assert_eq(u.position, before[i][0], "a kick moved a simulated position")
		assert_eq(u.radius, before[i][1], "a kick changed a collision radius")
	assert_eq(shooter.position, at, "the kick must not become a second position source")
	DisplayOptions.reset()

# --- what the kick is standing in for ---------------------------------------

## The issue asked whether the wind-up bar already draws at the moment of the
## loose. It does not: `CombatSim._fire_action` zeroes `action_ticks_left` and
## `wind_up_height` returns 0 for exactly that, so the bar vanishes at the loose
## and the only cue there today is something disappearing.
func test_the_wind_up_bar_is_gone_at_the_moment_of_the_loose() -> void:
	var u := _unit(0, CG.Team.PLAYER, Vector2.ZERO)
	u.current_action = SHOT
	u.action_ticks_total = 8
	u.action_ticks_left = 3
	var radius := UnitView.display_radius(u)
	assert_true(UnitView.wind_up_height(u, radius) > 0.0, "drawn while it is winding up")
	u.action_ticks_left = 0
	assert_eq(UnitView.wind_up_height(u, radius), 0.0,
		"and silent from the tick it fires, so a kick there fights nothing")
