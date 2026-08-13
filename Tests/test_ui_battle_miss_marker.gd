extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 14c: "X's Y fires" with silence after it read as a broken game.
## consume_events() spawns a marker into Arena on a MISS event, the same way
## it already does for DAMAGE/HEAL/DEATH. See Tests/test_ui_battle_death_marker.gd
## for why _ready() is called directly here.

func test_a_miss_event_spawns_a_marker_in_the_arena() -> void:
	var state := CombatState.new(1)
	var target := CombatUnit.new()
	target.id = 0
	target.display_name = "Rat"
	target.position = Vector2(10.0, 20.0)
	state.units.append(target)

	var view = BattleScene.instantiate()
	view._ready()
	view.state = state
	view.event_cursor = 0

	var arena_before := view.get_node("Arena").get_child_count()

	var miss := CombatEvent.make(CG.EventKind.MISS, 5)
	miss.target_id = 0
	state.emit(miss)
	view.consume_events()

	assert_eq(view.get_node("Arena").get_child_count(), arena_before + 1,
		"a MISS event must add a marker to the arena")
	view.free()

func test_a_miss_event_with_no_such_target_spawns_nothing() -> void:
	var state := CombatState.new(1)
	var view = BattleScene.instantiate()
	view._ready()
	view.state = state
	view.event_cursor = 0

	var arena_before := view.get_node("Arena").get_child_count()

	var miss := CombatEvent.make(CG.EventKind.MISS, 5)
	miss.target_id = 99
	state.emit(miss)
	view.consume_events()

	assert_eq(view.get_node("Arena").get_child_count(), arena_before)
	view.free()
