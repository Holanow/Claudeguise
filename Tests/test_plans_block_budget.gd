extends "res://Tests/TestCase.gd"


## Issue 790, the second half of it. wren's #269 branch made `PlanInterpreter`
## and `InspectPanel` agree on which row is over budget so that a row the
## screen calls "Inert" cannot fire anyway. The budget is now a flat row cap
## rather than WIS; this file re-proves the same two-sided guard against it.

func _block(op: StringName, args: Dictionary = {}) -> PlanBlock:
	return PlanFixtures.block(op, args)

func _plan(id: StringName, condition: PlanBlock, blocks: Array[PlanBlock]) -> Plan:
	var p := Plan.new()
	p.id = id
	p.condition = condition as ConditionBlock
	p.blocks = blocks
	return p

## `count` filler rows whose condition never holds, followed by one row named
## "strike" that always fires if the walk reaches it. Filler rows exist only to
## spend the row cap, so `count` rows before "strike" put it at row `count + 1`.
func _pawn_with_rows(count: int) -> PawnData:
	var pawn_class := ClassDef.new()
	pawn_class.id = &"rowcaptest"
	var pawn := PawnData.new()
	pawn.pawn_class = pawn_class
	pawn.plans = []
	for i in count:
		pawn.plans.append(_plan(StringName("filler_%d" % i), _block(&"self_resource_at_least", {"amount": 999}), [
			_block(&"target_self"),
			_block(&"use_action", {"action_id": &"warrior_strike"}),
		]))
	pawn.plans.append(_plan(&"strike", null, [
		_block(&"target_nearest_enemy"),
		_block(&"use_action", {"action_id": &"warrior_strike"}),
	]))
	return pawn

func _fight(pawn: PawnData) -> Array:
	var attacker := CombatUnit.new()
	attacker.id = 0
	attacker.team = CG.Team.PLAYER
	attacker.position = Vector2.ZERO
	attacker.hp_max = 100
	attacker.hp = 100
	attacker.resource_max = 100
	attacker.resource = 0
	attacker.focus_id = -1
	attacker.pawn = pawn

	var target := CombatUnit.new()
	target.id = 1
	target.team = CG.Team.ENEMY
	target.position = Vector2(10, 0)
	target.hp_max = 100
	target.hp = 100
	target.focus_id = -1

	var state := CombatState.new(0)
	state.units.append(attacker)
	state.units.append(target)
	return [state, attacker]


## The assertion whose absence let the mark and the behaviour disagree.
func test_a_row_past_the_cap_does_not_fire() -> void:
	var pawn := _pawn_with_rows(Balance.PLAN_ROW_CAP)
	var fight := _fight(pawn)
	var intent: Intent = PlanInterpreter.decide(fight[0], fight[1])
	assert_true(intent == null, "strike is row %d of a %d-row cap and must not fire" % [
		Balance.PLAN_ROW_CAP + 1, Balance.PLAN_ROW_CAP])


## The positive control. Without it the test above passes on an interpreter
## that refuses every plan, which is the other way to make the screen a liar.
func test_a_row_at_the_cap_fires() -> void:
	var pawn := _pawn_with_rows(Balance.PLAN_ROW_CAP - 1)
	var fight := _fight(pawn)
	var intent: Intent = PlanInterpreter.decide(fight[0], fight[1])
	assert_not_null(intent, "strike sits at row %d, inside the cap" % Balance.PLAN_ROW_CAP)
	assert_eq(intent.source_plan, &"strike")


func test_active_plan_count_stops_at_the_cap() -> void:
	var pawn := _pawn_with_rows(Balance.PLAN_ROW_CAP)
	assert_eq(pawn.plans.size(), Balance.PLAN_ROW_CAP + 1)
	assert_eq(PlanInterpreter.active_plan_count(pawn), Balance.PLAN_ROW_CAP)


## **The deliverable.** Not "the guard exists" but "the guard and the mark are
## the same rule". Both sides are exercised through the real thing: the screen
## is built and its labels read, the intent is taken from `decide`.
func test_the_screen_and_the_simulation_mark_the_same_row() -> void:
	var pawn := _pawn_with_rows(Balance.PLAN_ROW_CAP)

	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	var text := _all_label_text(panel._detail_box)
	var fight := _fight(pawn)
	var fired: Intent = PlanInterpreter.decide(fight[0], fight[1])
	assert_true(text.contains("Inert"), "row %d is past a %d-row cap: %s" % [
		Balance.PLAN_ROW_CAP + 1, Balance.PLAN_ROW_CAP, text])
	assert_true(text.contains("has 11 rows, capped at 10"), text)
	assert_true(fired == null, "and the pawn must not run the row the screen calls inert")
	panel.free()

func _all_label_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	for child in node.get_children():
		out += _all_label_text(child)
	return out
