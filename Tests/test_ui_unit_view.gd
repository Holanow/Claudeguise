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

# ---------------------------------------------------------------------------
# display_radius (issue 31: units read too small)
# ---------------------------------------------------------------------------

func test_display_radius_scales_the_raw_radius() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.radius = 22.0
	assert_almost_eq(UnitView.display_radius(u), 22.0 * UnitView.DISPLAY_SCALE, 0.001)

## The one regression that would matter most here: CombatSim reads
## unit.radius for real movement collision (Terrain.point_is_blocked), so a
## rendering fix that mutated it would be a balance change wearing a UI
## issue's clothes. display_radius must only ever read it.
func test_display_radius_does_not_mutate_the_units_own_radius() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.radius = 22.0
	UnitView.display_radius(u)
	assert_eq(u.radius, 22.0, "display scaling must never touch the simulation's own radius")

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

# ---------------------------------------------------------------------------
# concentration_count (issue 15)
# ---------------------------------------------------------------------------

func test_concentration_count_is_zero_with_no_attackers() -> void:
	var target := _make_unit(0, Vector2.ZERO)
	var bystander := _make_unit(1, Vector2(50.0, 0.0))
	assert_eq(UnitView.concentration_count(target, [target, bystander]), 0)

func test_concentration_count_counts_focused_attackers_only() -> void:
	var target := _make_unit(0, Vector2.ZERO)
	var attacker_a := _make_unit(1, Vector2(50.0, 0.0))
	attacker_a.focus_id = 0
	var attacker_b := _make_unit(2, Vector2(-50.0, 0.0))
	attacker_b.focus_id = 0
	var elsewhere := _make_unit(3, Vector2(0.0, 50.0))
	elsewhere.focus_id = 3
	var units := [target, attacker_a, attacker_b, elsewhere]
	assert_eq(UnitView.concentration_count(target, units), 2)

func test_concentration_count_ignores_dead_attackers() -> void:
	var target := _make_unit(0, Vector2.ZERO)
	var dead_attacker := _make_unit(1, Vector2(50.0, 0.0), false)
	dead_attacker.focus_id = 0
	assert_eq(UnitView.concentration_count(target, [target, dead_attacker]), 0)

# ---------------------------------------------------------------------------
# visual_offset (issue 15: the melee scrum)
# ---------------------------------------------------------------------------

func test_visual_offset_is_zero_when_nothing_is_close() -> void:
	var a := _make_unit(0, Vector2.ZERO)
	var b := _make_unit(1, Vector2(500.0, 0.0))
	assert_eq(UnitView.visual_offset(a, [a, b]), Vector2.ZERO)

func test_visual_offset_pushes_overlapping_units_apart() -> void:
	var a := _make_unit(0, Vector2(-5.0, 0.0))
	var b := _make_unit(1, Vector2(5.0, 0.0))
	var offset_a := UnitView.visual_offset(a, [a, b])
	var offset_b := UnitView.visual_offset(b, [a, b])
	assert_true(offset_a.x < 0.0, "a must be pushed further from b, i.e. further left")
	assert_true(offset_b.x > 0.0, "b must be pushed further from a, i.e. further right")

func test_visual_offset_never_exceeds_its_cap() -> void:
	# Several units stacked on the exact same point: a naive sum of pushes
	# could grow without bound. It must stay small enough that a unit never
	# reads somewhere misleadingly far from where it actually is.
	var units: Array = []
	for i in 6:
		units.append(_make_unit(i, Vector2.ZERO))
	var offset: Vector2 = UnitView.visual_offset(units[3], units)
	# Issue 31: the cap scales with DISPLAY_SCALE now, since visual_offset
	# reasons about the drawn (display) radius, not the raw simulation one.
	assert_true(offset.length() <= UnitView.display_radius(units[3]) * 1.5 + 0.01)

func test_visual_offset_is_deterministic_for_exactly_coincident_units() -> void:
	var a := _make_unit(0, Vector2.ZERO)
	var b := _make_unit(1, Vector2.ZERO)
	var first := UnitView.visual_offset(b, [a, b])
	var second := UnitView.visual_offset(b, [a, b])
	assert_eq(first, second, "the same fight must nudge the same unit the same way every time")

# ---------------------------------------------------------------------------
# should_show_label (issue 41: dense rooms piled enemy names on top of each other)
# ---------------------------------------------------------------------------

func test_should_show_label_is_always_true_for_the_party() -> void:
	var pawn := _make_unit(0, Vector2.ZERO)
	pawn.team = CG.Team.PLAYER
	assert_true(UnitView.should_show_label(pawn, [pawn]))

func test_should_show_label_is_false_for_an_untargeted_idle_enemy() -> void:
	var enemy := _make_unit(0, Vector2.ZERO)
	enemy.team = CG.Team.ENEMY
	assert_false(UnitView.should_show_label(enemy, [enemy]), "a standing, unengaged enemy doesn't need its name up permanently")

func test_should_show_label_is_true_for_an_enemy_under_focus() -> void:
	var enemy := _make_unit(0, Vector2.ZERO)
	enemy.team = CG.Team.ENEMY
	var attacker := _make_unit(1, Vector2(50.0, 0.0))
	attacker.focus_id = 0
	assert_true(UnitView.should_show_label(enemy, [enemy, attacker]))

func test_should_show_label_is_true_for_an_enemy_mid_wind_up() -> void:
	var enemy := _make_unit(0, Vector2.ZERO)
	enemy.team = CG.Team.ENEMY
	enemy.current_action = &"goblin_swing"
	enemy.action_ticks_left = 5
	assert_true(UnitView.should_show_label(enemy, [enemy]))

func test_should_show_label_is_false_for_an_enemy_with_stale_action_but_no_ticks_left() -> void:
	var enemy := _make_unit(0, Vector2.ZERO)
	enemy.team = CG.Team.ENEMY
	enemy.current_action = &"goblin_swing"
	enemy.action_ticks_left = 0
	assert_false(UnitView.should_show_label(enemy, [enemy]))
