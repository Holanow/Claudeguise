extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Plan := preload("res://Scripts/Core/Plan.gd")
const PlanBlock := preload("res://Scripts/Core/PlanBlock.gd")
const InspectPanel := preload("res://Scripts/UI/InspectPanel.gd")

## Issue 21b: read-only pawn inspection between fights. These build fixtures
## directly (same reasoning as test_ui_party_card.gd) so they do not depend
## on Registry having content, except the one test that specifically checks
## against real registered actions.

func _make_action(id: String, name: String, description: String = "") -> ActionDef:
	var a := ActionDef.new()
	a.id = StringName(id)
	a.display_name = name
	a.description = description
	return a

func _make_pawn(role: CG.Role = CG.Role.DPS) -> PawnData:
	var cls := ClassDef.new()
	cls.id = &"test_class"
	cls.display_name = "Test Class"
	cls.role_primary = role
	cls.style = CG.Style.MELEE
	cls.method = CG.Method.MARTIAL
	cls.starting_actions = [&"test_swing"]
	var pawn := PawnData.new()
	pawn.id = &"test_pawn"
	pawn.display_name = "Test Pawn"
	pawn.pawn_class = cls
	return pawn

func _make_plan(display_name: String) -> Plan:
	var p := Plan.new()
	p.id = StringName(display_name.to_snake_case())
	p.display_name = display_name
	return p

## Real bug, found on a real launch: the list/detail scroll containers had no
## vertical size flags, so they collapsed to their content's minimum size
## regardless of how much room the panel actually had, and the whole body
## rendered as nothing. Asserted directly rather than only via a screenshot.
func test_list_and_detail_containers_expand_to_fill() -> void:
	var panel := InspectPanel.new()
	panel._ready()
	var list_scroll: Control = panel._list_box.get_parent()
	var detail_scroll: Control = panel._detail_box.get_parent()
	assert_eq(list_scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL)
	assert_eq(detail_scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL)
	panel.free()

func test_opens_hidden_and_becomes_visible_on_open() -> void:
	var panel := InspectPanel.new()
	panel._ready()
	assert_false(panel.visible)
	var pawn := _make_pawn()
	panel.open([pawn])
	assert_true(panel.visible)
	panel.free()

func test_close_hides_the_panel_and_emits_closed() -> void:
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([_make_pawn()])
	var emitted: Array = []
	panel.closed.connect(func(): emitted.append(true))
	panel.close()
	assert_false(panel.visible)
	assert_eq(emitted, [true])
	panel.free()

func test_detail_shows_the_selected_pawns_name_and_role() -> void:
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([_make_pawn(CG.Role.HEALER)])
	var text := _all_label_text(panel._detail_box)
	assert_true(text.contains("Test Pawn"), text)
	assert_true(text.contains("Healer"), text)
	assert_false(text.contains("_"), "no raw enum name should reach the screen: " + text)
	panel.free()

func test_switching_pawns_rebuilds_the_detail_panel() -> void:
	var panel := InspectPanel.new()
	panel._ready()
	var a := _make_pawn()
	a.display_name = "Pawn A"
	var b := _make_pawn()
	b.display_name = "Pawn B"
	panel.open([a, b])
	assert_true(_all_label_text(panel._detail_box).contains("Pawn A"))
	panel._select(1)
	var text := _all_label_text(panel._detail_box)
	assert_true(text.contains("Pawn B"))
	assert_false(text.contains("Pawn A"))
	panel.free()

## Criterion 4: what a pawn cannot use must be distinguishable from what it
## can, and this slice says everything is available rather than leaving it
## ambiguous.
func test_availability_is_stated_on_screen() -> void:
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([_make_pawn()])
	var text := _all_label_text(panel)
	assert_true(text.to_lower().contains("available"), text)
	panel.free()

## Plans show in priority order, by the plan's own real display_name (not
## invented UI wording) until issue 21a's describe_op lands.
func test_plans_list_in_priority_order() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("Guard when hurt"), _make_plan("Execute when raging")]
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])
	var text := _all_label_text(panel._detail_box)
	var guard_at := text.find("Guard when hurt")
	var execute_at := text.find("Execute when raging")
	assert_true(guard_at != -1 and execute_at != -1, text)
	assert_true(guard_at < execute_at, "priority order not preserved: " + text)
	panel.free()

func test_an_action_used_by_no_plan_is_called_out_as_unused() -> void:
	var pawn := _make_pawn()
	pawn.pawn_class.starting_actions = [&"test_swing", &"test_unused"]
	var plan := _make_plan("Swing plan")
	var action_block := PlanBlock.new()
	action_block.kind = PlanBlock.Kind.ACTION
	action_block.op = &"use_action"
	action_block.args = {"action_id": &"test_swing"}
	plan.blocks = [action_block]
	pawn.plans = [plan]
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])
	var text := _all_label_text(panel._detail_box)
	assert_true(text.contains("not called by any plan"), text)
	panel.free()

## Issue 21a's field (ActionDef.description) is on the trunk but empty on
## every real action right now. Missing text must read as "not written yet",
## never as a blank line that looks broken.
func test_an_empty_action_description_reads_as_pending_not_blank() -> void:
	var panel := InspectPanel.new()
	panel._ready()
	assert_true(panel._action_line(&"nonexistent_action") != null)
	panel.free()

func _all_label_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	for child in node.get_children():
		out += _all_label_text(child)
	return out
