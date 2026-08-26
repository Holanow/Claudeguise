extends "res://Tests/TestCase.gd"


## Issue 269, the second half of it. wren's branch made `plan_block_budget` read
## equipment WIS and made `InspectPanel` dim and label every plan row past the
## budget. **Nothing enforced it.** `PlanInterpreter.decide` walked
## `unit.pawn.plans` with no reference to the budget at all, so the budget was
## enforced only by the plan editor refusing to *add* a row -- and a row the
## screen labelled "Inert" fired exactly like a live one.

func _block(kind: PlanBlock.Kind, op: StringName, args: Dictionary = {}) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = kind
	b.op = op
	b.args = args
	return b

func _plan(id: StringName, condition: PlanBlock, blocks: Array[PlanBlock]) -> Plan:
	var p := Plan.new()
	p.id = id
	p.condition = condition
	p.blocks = blocks
	return p

## A pawn with two 2-block plans and 2 base WIS, so it needs 2 points of
## equipment WIS to pay for the second row.
func _pawn_with_two_plans() -> PawnData:
	var pawn_class := ClassDef.new()
	pawn_class.id = &"budgettest"
	pawn_class.base_attributes = {"WIS": 2}
	var pawn := PawnData.new()
	pawn.pawn_class = pawn_class
	pawn.plans = [
		_plan(&"never", _block(PlanBlock.Kind.CONDITION, &"self_resource_at_least", {"amount": 999}), [
			_block(PlanBlock.Kind.TARGETING, &"target_self"),
			_block(PlanBlock.Kind.ACTION, &"use_action", {"action_id": &"warrior_strike"}),
		]),
		_plan(&"strike", null, [
			_block(PlanBlock.Kind.TARGETING, &"target_nearest_enemy"),
			_block(PlanBlock.Kind.ACTION, &"use_action", {"action_id": &"warrior_strike"}),
		]),
	]
	return pawn

func _robes() -> EquipmentDef:
	var armor := EquipmentDef.new()
	armor.slot = EquipmentDef.Slot.ARMOR
	armor.attribute_flat = {CG.Attribute.WIS: 2}
	return armor

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
func test_a_plan_past_the_block_budget_does_not_fire() -> void:
	var pawn := _pawn_with_two_plans()
	var fight := _fight(pawn)
	var intent: Intent = PlanInterpreter.decide(fight[0], fight[1])
	assert_true(intent == null, "row two costs blocks 3 and 4 of a 2-block budget and must not fire")


## The positive control. Without it the test above passes on an interpreter that
## refuses every plan, which is the other way to make the screen a liar.
func test_the_same_plan_fires_once_equipment_pays_for_it() -> void:
	var pawn := _pawn_with_two_plans()
	pawn.armor = _robes()
	var fight := _fight(pawn)
	var intent: Intent = PlanInterpreter.decide(fight[0], fight[1])
	assert_not_null(intent, "2 WIS on armor buys the two blocks row two needs")
	assert_eq(intent.source_plan, &"strike")


## The player's actual route: author to the wider budget, then unequip. The rows
## are not deleted and the edit is not refused -- they stop firing, which is what
## the screen has to be saying.
func test_taking_the_wis_armour_off_strands_the_row_it_paid_for() -> void:
	var pawn := _pawn_with_two_plans()
	pawn.armor = _robes()
	assert_eq(PlanInterpreter.active_plan_count(pawn), 2)

	pawn.armor = null
	assert_eq(PlanInterpreter.active_plan_count(pawn), 1, "the budget fell to 2, so only row one is paid for")
	assert_eq(pawn.plans.size(), 2, "and the row itself is still there for the player to fix")


## A pawn inside its budget runs every row. The negative: a guard that fires on
## healthy input is a guard nobody can trust, and both tests above would pass on
## one that always refused the last row.
func test_nothing_is_skipped_when_the_plans_fit() -> void:
	var pawn := _pawn_with_two_plans()
	pawn.pawn_class.base_attributes = {"WIS": 8}
	assert_eq(PlanInterpreter.active_plan_count(pawn), 2)
	var fight := _fight(pawn)
	var intent: Intent = PlanInterpreter.decide(fight[0], fight[1])
	assert_not_null(intent)
	assert_eq(intent.source_plan, &"strike")


## **The deliverable.** Not "the guard exists" but "the guard and the mark are
## the same rule". Both sides are exercised through the real thing: the screen is
## built and its labels read, the intent is taken from `decide`, at both budgets.
func test_the_screen_and_the_simulation_mark_the_same_row() -> void:
	var pawn := _pawn_with_two_plans()

	pawn.armor = _robes()
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	var equipped := _all_label_text(panel._detail_box)
	var fight_equipped := _fight(pawn)
	var fired_equipped: Intent = PlanInterpreter.decide(fight_equipped[0], fight_equipped[1])
	assert_false(equipped.contains("Inert"), "nothing is inert at 4 of 4: " + equipped)
	assert_not_null(fired_equipped, "and the pawn runs the row the screen shows as live")

	pawn.armor = null
	panel._build_detail(pawn)
	var stripped := _all_label_text(panel._detail_box)
	var fight_stripped := _fight(pawn)
	var fired_stripped: Intent = PlanInterpreter.decide(fight_stripped[0], fight_stripped[1])
	assert_true(stripped.contains("Inert"), "row two is past a 2-block budget: " + stripped)
	assert_true(stripped.contains("needs 4 WIS, this pawn has 2"), stripped)
	assert_true(fired_stripped == null, "and the pawn must not run the row the screen calls inert")
	panel.free()

func _all_label_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	for child in node.get_children():
		out += _all_label_text(child)
	return out
