extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 516: the struck body squashes and the attacker rocks back, both in the
## view and neither of them anywhere the simulation can read.

func _unit(id: int, team: CG.Team, at: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.display_name = "u%d" % id
	u.position = at
	u.hp = 10
	u.hp_max = 10
	return u

## Two bodies with views, close enough to be in melee unless a test moves them.
func _view_with_pair(apart: float = 20.0) -> Node2D:
	var state := CombatState.new(1)
	state.units.append(_unit(0, CG.Team.PLAYER, Vector2.ZERO))
	state.units.append(_unit(1, CG.Team.ENEMY, Vector2(apart, 0.0)))
	var view = in_tree(BattleScene.instantiate())
	view.state = state
	view.event_cursor = 0
	view._rebuild_units()
	return view

func _damage(source: int, target: int, action: StringName) -> CombatEvent:
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = source
	e.target_id = target
	e.action_id = action
	e.amount = 3
	return e

# --- the shape of the decay ------------------------------------------------

func test_the_squash_is_widest_at_the_moment_of_impact() -> void:
	var at_impact := UnitView.squash_scale(0.0)
	assert_almost_eq(at_impact.x, 1.0 + UnitView.SQUASH_AMOUNT)
	assert_almost_eq(at_impact.y, 1.0 - UnitView.SQUASH_AMOUNT)

func test_the_squash_is_gone_by_the_end_of_its_span() -> void:
	assert_eq(UnitView.squash_scale(UnitView.SQUASH_SECONDS), Vector2.ONE)
	assert_eq(UnitView.squash_scale(99.0), Vector2.ONE)
	assert_eq(UnitView.squash_scale(INF), Vector2.ONE)

## Fast in, slow out. Halfway through the span the body must be most of the way
## home already; a linear decay would sit at exactly half and read as a slide.
func test_the_recovery_eases_rather_than_running_linear() -> void:
	var half := UnitView.impact_decay(UnitView.SQUASH_SECONDS * 0.5, UnitView.SQUASH_SECONDS)
	assert_true(half < 0.35, "cubic ease-out, not linear: got %.3f at the halfway point" % half)
	var first := UnitView.impact_decay(0.0, UnitView.SQUASH_SECONDS) - \
		UnitView.impact_decay(UnitView.SQUASH_SECONDS * 0.1, UnitView.SQUASH_SECONDS)
	var last := UnitView.impact_decay(UnitView.SQUASH_SECONDS * 0.9, UnitView.SQUASH_SECONDS)
	assert_true(first > last, "the first tenth must move further than the last")

func test_the_recoil_points_away_and_decays_to_nothing() -> void:
	var out := UnitView.recoil_offset(0.0, Vector2.RIGHT)
	assert_almost_eq(out.x, UnitView.RECOIL_PIXELS)
	assert_almost_eq(out.y, 0.0)
	assert_eq(UnitView.recoil_offset(UnitView.RECOIL_SECONDS, Vector2.RIGHT), Vector2.ZERO)

# --- what a damage event does ----------------------------------------------

func test_a_melee_hit_squashes_the_target_and_recoils_the_attacker() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair()
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()

	var struck: Node2D = view._unit_views[0]
	var attacker: Node2D = view._unit_views[1]
	assert_true(struck.impact_active(), "the struck body should be squashing")
	assert_true(attacker.impact_active(), "the attacker should be recoiling")
	assert_ne(UnitView.squash_scale(struck._squash_age), Vector2.ONE)
	# Unit 1 stands to the right of unit 0, so it is thrown further right.
	assert_true(attacker._recoil_direction.x > 0.9,
		"recoil points away from the target, got %.2f" % attacker._recoil_direction.x)
	DisplayOptions.reset()

## Poison, burn, bleed and hazard damage all emit one DAMAGE per unit per tick
## with no action on it. Ungated, a poisoned pawn shivers fifteen times a second
## and the recoil points at whoever applied the status, wherever they are.
func test_damage_over_time_moves_nothing() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair()
	view.state.emit(_damage(1, 0, &""))
	view.consume_events()

	assert_false(view._unit_views[0].impact_active(), "a poison tick is not a blow")
	assert_false(view._unit_views[1].impact_active())
	DisplayOptions.reset()

## A projectile's DAMAGE lands a second or more after it was loosed, so an
## archer rocking back at that moment says the wrong thing about what caused
## what. The target still squashes: something did hit it.
func test_a_hit_from_across_the_room_squashes_but_does_not_recoil() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair(600.0)
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()

	assert_true(view._unit_views[0].impact_active(), "the arrow still landed on somebody")
	assert_false(view._unit_views[1].impact_active(), "the archer loosed a second ago")
	DisplayOptions.reset()

# --- the negative cases ----------------------------------------------------

func test_the_toggle_off_leaves_every_body_exactly_where_it_was() -> void:
	DisplayOptions.set_enabled(&"impact_squash", false)
	var view := _view_with_pair()
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()

	for id in [0, 1]:
		var body: Node2D = view._unit_views[id]
		assert_false(body.impact_active())
		assert_false(body.is_processing(), "nothing to animate, so nothing to process")
		assert_eq(UnitView.squash_scale(body._squash_age), Vector2.ONE)
	DisplayOptions.reset()

## An effect that never ends is a silent 60Hz redraw on every unit for the rest
## of the fight, which is the whole frame budget this issue has to stay inside.
func test_the_effect_ends_and_gives_the_frame_back() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair()
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()

	var struck: Node2D = view._unit_views[0]
	assert_true(struck.is_processing())
	for i in 60:
		struck._process(1.0 / 60.0)
	assert_false(struck.impact_active(), "one second is four spans")
	assert_false(struck.is_processing(), "and it must stop asking for frames")
	assert_eq(UnitView.squash_scale(struck._squash_age), Vector2.ONE)
	assert_eq(UnitView.recoil_offset(struck._recoil_age, Vector2.RIGHT), Vector2.ZERO)
	DisplayOptions.reset()

func test_an_untouched_body_never_processes() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair()
	for id in [0, 1]:
		assert_false(view._unit_views[id].is_processing(),
			"a body nothing has hit costs no frame time")
	DisplayOptions.reset()

# --- the line that must not be crossed --------------------------------------

## Visual recoil only. The offset lives in the view and the simulation may not
## be able to tell it happened.
func test_the_impact_never_reaches_the_simulation() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair()
	var before: Array = []
	for u in view.state.units:
		before.append([u.position, u.radius])
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()
	var struck: Node2D = view._unit_views[0]
	for i in 4:
		struck._process(1.0 / 60.0)

	for i in view.state.units.size():
		var u: CombatUnit = view.state.units[i]
		assert_eq(u.position, before[i][0], "a recoil moved a simulated position")
		assert_eq(u.radius, before[i][1], "a squash changed a collision radius")
	DisplayOptions.reset()

## The node's own position is the interpolated one from #501 and stays that.
## Everything this issue adds is a draw transform inside the body.
func test_the_view_keeps_one_position_source() -> void:
	DisplayOptions.set_enabled(&"impact_squash", true)
	var view := _view_with_pair()
	var struck: Node2D = view._unit_views[0]
	var at := struck.position
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()
	struck._process(1.0 / 60.0)
	assert_eq(struck.position, at, "the impact must not become a second position source")
	DisplayOptions.reset()
