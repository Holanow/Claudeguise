extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const UnitView := preload("res://Scripts/UI/UnitView.gd")

## UnitView reads CombatUnit directly for position and bars (the issue allows
## this; only "things that happened" must come from events). These tests check
## it tracks position and alive/dead visibility without needing to render.

func _make_unit(id: int, pos: Vector2, alive: bool = true) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.position = pos
	u.hp = 5
	u.hp_max = 10
	u.alive = alive
	u.display_name = "Test"
	return u

func test_bind_places_the_view_at_the_unit_position() -> void:
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, Vector2(100.0, -50.0)))
	var view := UnitView.new()
	view.bind(state, 0)
	assert_eq(view.position, Vector2(100.0, -50.0))
	view.free()

func test_sync_follows_a_moving_unit() -> void:
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, Vector2.ZERO))
	var view := UnitView.new()
	view.bind(state, 0)
	state.units[0].position = Vector2(10.0, 20.0)
	view.sync(state)
	assert_eq(view.position, Vector2(10.0, 20.0))
	view.free()

func test_dead_unit_is_not_visible() -> void:
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, Vector2.ZERO, true))
	var view := UnitView.new()
	view.bind(state, 0)
	assert_true(view.visible)

	state.units[0].alive = false
	view.sync(state)
	assert_false(view.visible, "a dead unit's view must not stay visible")
	view.free()

func test_status_tags_are_empty_for_an_unaffected_unit() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	assert_true(UnitView.status_tags(u).is_empty())

func test_status_tags_names_a_stun() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.statuses[CG.Status.STUN] = 100
	assert_eq(UnitView.status_tags(u), ["STUN"])

func test_status_tags_names_being_out_of_resource() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.resource_max = 10
	u.resource = 0
	assert_eq(UnitView.status_tags(u), ["OOM"])

func test_status_tags_does_not_flag_a_unit_with_no_resource_pool() -> void:
	# resource_max == 0 means "this unit has no resource", not "empty resource".
	var u := _make_unit(0, Vector2.ZERO)
	u.resource_max = 0
	u.resource = 0
	assert_true(UnitView.status_tags(u).is_empty())

func test_status_tags_combines_stun_and_oom() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.statuses[CG.Status.STUN] = 100
	u.resource_max = 10
	u.resource = 0
	assert_eq(UnitView.status_tags(u), ["STUN", "OOM"])

func test_crowd_rank_is_zero_when_units_are_far_apart() -> void:
	var a := _make_unit(0, Vector2.ZERO)
	var b := _make_unit(1, Vector2(500.0, 0.0))
	assert_eq(UnitView.crowd_rank(a, [a, b]), 0)
	assert_eq(UnitView.crowd_rank(b, [a, b]), 0)

func test_crowd_rank_only_moves_the_higher_id() -> void:
	# Deterministic by id: two views of the same fight must agree on which
	# of two overlapping units' labels moves, not on whichever happened to
	# be iterated or drawn first.
	var a := _make_unit(0, Vector2.ZERO)
	var b := _make_unit(1, Vector2(5.0, 0.0))
	assert_eq(UnitView.crowd_rank(a, [a, b]), 0, "the lower id must not move")
	assert_eq(UnitView.crowd_rank(b, [a, b]), 1, "the higher id steps up once")

func test_crowd_rank_stacks_with_each_additional_close_lower_id() -> void:
	var a := _make_unit(0, Vector2.ZERO)
	var b := _make_unit(1, Vector2(5.0, 0.0))
	var c := _make_unit(2, Vector2(-5.0, 0.0))
	assert_eq(UnitView.crowd_rank(c, [a, b, c]), 2)

func test_crowd_rank_ignores_dead_units() -> void:
	var a := _make_unit(0, Vector2.ZERO, false)
	var b := _make_unit(1, Vector2(5.0, 0.0))
	assert_eq(UnitView.crowd_rank(b, [a, b]), 0, "a dead unit's old label is gone too, nothing to avoid")
