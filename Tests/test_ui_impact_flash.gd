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

## Issue 276. The ring is drawn at the size of a body, so a ring that is not on
## a body is marking nothing. Asserted against a real fight rather than a hand
## built frame: the old anchor missed both ways -- it never moved when the
## target walked, and it ignored UnitView's scrum nudge even standing still.
func test_every_live_flash_sits_on_its_targets_drawn_body() -> void:
	var view := _make_real_fight_view()
	var arena := view.get_node("Arena")
	var flash_frames := 0
	var off_body := 0
	for frame in 400:
		if view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		view._process(CG.TICK_SECONDS)
		for child in arena.get_children():
			if child.get_script() != ImpactFlash or child.is_queued_for_deletion():
				continue
			child._process(CG.TICK_SECONDS)
			if child.is_queued_for_deletion():
				continue
			flash_frames += 1
			if not _sits_on_a_body(child.position, view):
				off_body += 1
	assert_true(flash_frames > 0, "the fight produced no impact flashes to measure")
	assert_eq(off_body, 0, "%d of %d flash-frames drew the ring off every body" % [off_body, flash_frames])
	view.free()

func _sits_on_a_body(p: Vector2, view: Node2D) -> bool:
	for id in view._unit_views:
		if view._unit_views[id].position.is_equal_approx(p):
			return true
	return false

func _make_real_fight_view() -> Node2D:
	var party: Array[PawnData] = []
	var class_ids := Registry.all_class_ids()
	for i in mini(4, class_ids.size()):
		party.append(PawnFactory.make_starter_pawn(class_ids[i], StringName("p%d" % i), String(class_ids[i])))
	var encounter = Registry.get_encounter(Registry.all_encounter_ids()[0])
	var view = BattleScene.instantiate()
	view._ready()
	view.state = CombatSim.build(party, encounter, 7)
	view.event_cursor = 0
	return view
