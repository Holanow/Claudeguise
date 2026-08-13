extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const BattleView := preload("res://Scripts/UI/BattleView.gd")

## BattleView reads CombatEvent, never polls CombatUnit for "what happened".
## These tests build a CombatState by hand, per the issue: CombatSim is wren's
## stub today, so the fixture stands in for a real fight without waiting on it.
## consume_events() is exercised directly, bypassing begin()/_ready(), because
## begin() calls CombatSim.build() which is not implemented yet.

func _make_state_with_units() -> CombatState:
	var state := CombatState.new(1)
	var a := CombatUnit.new()
	a.id = 0
	a.team = CG.Team.PLAYER
	a.display_name = "Warrior"
	state.units.append(a)
	var b := CombatUnit.new()
	b.id = 1
	b.team = CG.Team.ENEMY
	b.display_name = "Rat"
	state.units.append(b)
	return state

func test_consume_events_advances_the_cursor() -> void:
	var state := _make_state_with_units()
	var view := BattleView.new()
	view.state = state
	view.event_cursor = 0

	state.emit(CombatEvent.make(CG.EventKind.FIGHT_START, 0))
	view.consume_events()
	assert_eq(view.event_cursor, 1)

	state.emit(CombatEvent.make(CG.EventKind.DAMAGE, 1))
	state.emit(CombatEvent.make(CG.EventKind.DAMAGE, 1))
	view.consume_events()
	assert_eq(view.event_cursor, 3)
	view.free()

func test_consume_events_does_not_reprocess_old_events() -> void:
	var state := _make_state_with_units()
	var view := BattleView.new()
	view.state = state
	view.event_cursor = 0

	for i in 3:
		state.emit(CombatEvent.make(CG.EventKind.DAMAGE, i))
	view.consume_events()
	assert_eq(view.event_cursor, 3)

	# No new events: cursor must not move or double-count.
	view.consume_events()
	assert_eq(view.event_cursor, 3)
	view.free()

## Issue 24: CombatLogView.line_for_event now drops a poison/burn tick's log
## line, and the two paths (log, floater) both read straight from the event
## in consume_events() -- neither calls the other. This is the check that the
## affliction really is "still visible somewhere" once the log stops saying
## it: the floater must fire from the event itself regardless of what the log
## chose to print, which is what makes dropping the line safe rather than
## just quieter.
func test_a_poison_shaped_damage_event_still_spawns_a_floater_though_the_log_drops_it() -> void:
	var state := _make_state_with_units()
	var view := BattleView.new()
	view.state = state
	view.event_cursor = 0
	view._arena = Node2D.new()

	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = -1
	e.target_id = 1
	e.amount = 1
	e.amount_before_mitigation = 1
	e.status = CG.Status.POISON
	state.emit(e)
	view.consume_events()

	assert_eq(view._arena.get_child_count(), 1,
		"a poison tick must still spawn a floating number even though the log line is dropped")
	view._arena.free()
	view.free()
