extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 8: a death should land as an event, not as a unit quietly vanishing.

func test_a_death_event_spawns_a_marker_in_the_arena() -> void:
	var state := CombatState.new(1)
	var target := CombatUnit.new()
	target.id = 0
	target.display_name = "Rat"
	target.position = Vector2(10.0, 20.0)
	state.units.append(target)

	var view = in_tree(BattleScene.instantiate())
	view.state = state
	view.event_cursor = 0

	var arena_before := view.get_node("Arena").get_child_count()

	var death := CombatEvent.make(CG.EventKind.DEATH, 5)
	death.target_id = 0
	state.emit(death)
	view.consume_events()

	assert_eq(view.get_node("Arena").get_child_count(), arena_before + 1,
		"a DEATH event must add a marker to the arena")

func test_a_death_event_with_no_such_unit_spawns_nothing() -> void:
	var state := CombatState.new(1)
	var view = in_tree(BattleScene.instantiate())
	view.state = state
	view.event_cursor = 0

	var arena_before := view.get_node("Arena").get_child_count()

	var death := CombatEvent.make(CG.EventKind.DEATH, 5)
	death.target_id = 99
	state.emit(death)
	view.consume_events()

	assert_eq(view.get_node("Arena").get_child_count(), arena_before)
