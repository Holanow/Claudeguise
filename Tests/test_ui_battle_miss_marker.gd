extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 14c: "X's Y fires" with silence after it read as a broken game.

func test_a_miss_event_spawns_a_marker_in_the_arena() -> void:
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

	var miss := CombatEvent.make(CG.EventKind.MISS, 5)
	miss.target_id = 0
	state.emit(miss)
	view.consume_events()

	assert_eq(view.get_node("Arena").get_child_count(), arena_before + 1,
		"a MISS event must add a marker to the arena")

func test_a_miss_event_with_no_such_target_spawns_nothing() -> void:
	var state := CombatState.new(1)
	var view = in_tree(BattleScene.instantiate())
	view.state = state
	view.event_cursor = 0

	var arena_before := view.get_node("Arena").get_child_count()

	var miss := CombatEvent.make(CG.EventKind.MISS, 5)
	miss.target_id = 99
	state.emit(miss)
	view.consume_events()

	assert_eq(view.get_node("Arena").get_child_count(), arena_before)
