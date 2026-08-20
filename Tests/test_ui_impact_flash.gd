extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## PLAYTEST-NOTES 4: "every class needs an attack asset ... so I know what's
## up" -- melee had nothing but DamageFloater's number where a hit landed.

func _make_view_with_target(pos: Vector2, hp: int = 10) -> Node2D:
	var state := CombatState.new(1)
	var target := CombatUnit.new()
	target.id = 0
	target.team = CG.Team.PLAYER
	target.display_name = "Rat"
	target.position = pos
	target.hp = hp
	target.hp_max = hp
	state.units.append(target)

	var view = BattleScene.instantiate()
	view._ready()
	view.state = state
	view.event_cursor = 0
	return view

func test_a_damage_event_spawns_an_impact_flash_at_the_targets_position() -> void:
	var view := _make_view_with_target(Vector2(30.0, -10.0))
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.target_id = 0
	e.amount = 5
	e.amount_before_mitigation = 5
	e.damage_type = CG.DamageType.FIRE
	view.state.emit(e)
	view.consume_events()

	var arena := view.get_node("Arena")
	var found: Node2D = null
	for child in arena.get_children():
		if child.get_script() == ImpactFlash:
			found = child
	assert_not_null(found, "expected an ImpactFlash spawned for the DAMAGE event")
	assert_eq(found.position, Vector2(30.0, -10.0))
	view.free()

func test_a_heal_event_also_spawns_an_impact_flash() -> void:
	var view := _make_view_with_target(Vector2.ZERO)
	var e := CombatEvent.make(CG.EventKind.HEAL, 1)
	e.target_id = 0
	e.amount = 4
	e.damage_type = CG.DamageType.DIVINE
	view.state.emit(e)
	view.consume_events()

	var arena := view.get_node("Arena")
	var found := false
	for child in arena.get_children():
		if child.get_script() == ImpactFlash:
			found = true
	assert_true(found, "a heal landing is an event too, not only damage")
	view.free()

func test_a_miss_does_not_spawn_an_impact_flash() -> void:
	var view := _make_view_with_target(Vector2.ZERO)
	var e := CombatEvent.make(CG.EventKind.MISS, 1)
	e.target_id = 0
	view.state.emit(e)
	view.consume_events()

	var arena := view.get_node("Arena")
	for child in arena.get_children():
		assert_ne(child.get_script(), ImpactFlash, "nothing landed, so nothing should flash")
	view.free()

# ---------------------------------------------------------------------------
# ImpactFlash itself: purely cosmetic, wall-clock driven, same shape as
# DamageFloater.

func test_show_starts_the_clock_and_shows_visible() -> void:
	var flash := ImpactFlash.new()
	flash.flash(CG.DamageType.WATER, 20.0)
	assert_true(flash.is_processing())
	flash.free()

func test_impact_flash_frees_itself_after_its_lifetime() -> void:
	var flash := ImpactFlash.new()
	flash.flash(CG.DamageType.WATER, 20.0)
	flash._process(ImpactFlash.LIFETIME_SECONDS + 0.01)
	assert_true(not is_instance_valid(flash) or flash.is_queued_for_deletion())
