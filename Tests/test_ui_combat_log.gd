extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const CombatLogView := preload("res://Scripts/UI/CombatLogView.gd")

## CombatLogView.line_for_event is pure formatting split out of the Control so
## it can be checked without a live RichTextLabel. This is the half of issue 3
## that proves "a hit landed small because it was mitigated" is readable, not
## just "a number changed".

func _make_state() -> CombatState:
	var state := CombatState.new(1)
	var attacker := CombatUnit.new()
	attacker.id = 0
	attacker.team = CG.Team.PLAYER
	attacker.display_name = "Warrior"
	state.units.append(attacker)

	var target := CombatUnit.new()
	target.id = 1
	target.team = CG.Team.ENEMY
	target.display_name = "Rat"
	state.units.append(target)
	return state

func test_damage_line_names_actor_target_and_amount() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = 0
	e.target_id = 1
	e.amount = 7
	e.amount_before_mitigation = 7
	e.damage_type = CG.DamageType.PHYSICAL
	var line := view.line_for_event(state, e)
	assert_true(line.contains("Warrior"), line)
	assert_true(line.contains("Rat"), line)
	assert_true(line.contains("7"), line)
	view.free()

func test_mitigated_hit_shows_the_raw_roll_too() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = 0
	e.target_id = 1
	e.amount = 4
	e.amount_before_mitigation = 10
	var line := view.line_for_event(state, e)
	assert_true(line.contains("4"), line)
	assert_true(line.contains("10"), line)
	view.free()

func test_unmitigated_hit_does_not_mention_a_second_number() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = 0
	e.target_id = 1
	e.amount = 7
	e.amount_before_mitigation = 7
	var line := view.line_for_event(state, e)
	assert_false(line.contains("before mitigation"), line)
	view.free()

func test_death_line_names_the_unit() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DEATH, 3)
	e.target_id = 1
	var line := view.line_for_event(state, e)
	assert_true(line.contains("Rat"), line)
	assert_true(line.contains("dies"), line)
	view.free()

func test_miss_line_names_actor_action_and_target() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.MISS, 1)
	e.source_id = 0
	e.target_id = 1
	e.action_id = &"geyser_scald"
	var line := view.line_for_event(state, e)
	assert_true(line.contains("Warrior"), line)
	assert_true(line.contains("Rat"), line)
	assert_true(line.contains("misses"), line)
	view.free()

## Issue 14's own finding: a miss, a landed hit, and a hit fully absorbed by
## mitigation are three different events and a player must be able to tell
## them apart. Three different sentence shapes, checked pairwise.
func test_miss_reads_differently_from_a_landed_hit_and_a_fully_mitigated_one() -> void:
	var state := _make_state()
	var view := CombatLogView.new()

	var miss := CombatEvent.make(CG.EventKind.MISS, 1)
	miss.source_id = 0
	miss.target_id = 1
	miss.action_id = &"swing"

	var landed := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	landed.source_id = 0
	landed.target_id = 1
	landed.amount = 7
	landed.amount_before_mitigation = 7

	var absorbed := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	absorbed.source_id = 0
	absorbed.target_id = 1
	absorbed.amount = 0
	absorbed.amount_before_mitigation = 12

	var miss_line := view.line_for_event(state, miss)
	var landed_line := view.line_for_event(state, landed)
	var absorbed_line := view.line_for_event(state, absorbed)

	assert_ne(miss_line, landed_line)
	assert_ne(miss_line, absorbed_line)
	assert_ne(landed_line, absorbed_line)
	assert_true(miss_line.contains("misses"))
	assert_false(landed_line.contains("misses"))
	assert_true(absorbed_line.contains("before mitigation"), "a fully absorbed hit must still show the raw roll, not read like a miss")
	view.free()
