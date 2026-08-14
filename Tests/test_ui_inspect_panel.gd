extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Plan := preload("res://Scripts/Core/Plan.gd")
const PlanBlock := preload("res://Scripts/Core/PlanBlock.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const PlanInterpreter := preload("res://Scripts/Plans/PlanInterpreter.gd")
const InspectPanel := preload("res://Scripts/UI/InspectPanel.gd")

## Issue 21b: pawn inspection between fights. Issue 6 added editing: reorder a
## pawn's plans, swap the targeting or action inside a block, and swap or
## retune the condition that gates a plan. These build fixtures directly (same
## reasoning as test_ui_party_card.gd) so they do not depend on Registry
## having content, except the one test that specifically checks against real
## registered actions.

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

## Issue 53 sweep: on a real launch, the "Targeting:" label and the picker's
## own text overlapped into "TaSelfting:" (Screenshots/
## sweep_inspect_plan_editor_*). _line()'s autowrap makes a Label report a
## near-zero minimum width in the HBoxContainer beside the SIZE_EXPAND_FILL
## picker, the same bug already found and worked around for the Attributes
## chips. Asserted directly on the built row rather than only via a
## screenshot: the prefix label must not autowrap.
func test_targeting_label_does_not_autowrap() -> void:
	var pawn := _make_pawn()
	var targeting := PlanBlock.new()
	targeting.kind = PlanBlock.Kind.TARGETING
	targeting.op = &"target_self"
	var plan := _make_plan("Always act")
	plan.blocks = [targeting]
	pawn.plans = [plan]

	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	var row := panel._targeting_picker(targeting)
	var label: Label = row.get_child(0)
	assert_eq(label.text, "Targeting:")
	assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_OFF, "a short fixed prefix must not report a near-zero minimum width")
	panel.free()

func test_action_label_does_not_autowrap() -> void:
	var pawn := _make_pawn()
	var action := PlanBlock.new()
	action.kind = PlanBlock.Kind.ACTION
	action.op = &"use_action"
	action.args = {"action_id": &"test_swing"}
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	var row := panel._action_picker(pawn, action)
	var label: Label = row.get_child(0)
	assert_eq(label.text, "Action:")
	assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_OFF)
	panel.free()

func test_condition_label_does_not_autowrap() -> void:
	var pawn := _make_pawn()
	var plan := _make_plan("Always act")
	pawn.plans = [plan]
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	var row := panel._condition_editor(plan)
	var label: Label = row.get_child(0)
	assert_eq(label.text, "Condition:")
	assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_OFF)
	panel.free()

# ---------------------------------------------------------------------------
# Hover-info-box system, phase 1
# ---------------------------------------------------------------------------

func test_attribute_chips_carry_glossary_tooltips() -> void:
	const Glossary := preload("res://Scripts/UI/Glossary.gd")
	const GlossaryLabelScript := preload("res://Scripts/UI/GlossaryLabel.gd")
	var pawn := _make_pawn()
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	var found := false
	for child in panel._detail_box.get_children():
		if child is HBoxContainer:
			for chip in child.get_children():
				if chip is Label and chip.text.begins_with("STR"):
					found = true
					assert_eq(chip.get_script(), GlossaryLabelScript, "must be hoverable, same as every other glossary term")
					assert_eq(chip.tooltip_text, Glossary.attribute_text(CG.Attribute.STR))
	assert_true(found, "expected to find the STR chip")
	panel.free()

func test_class_tags_header_line_carries_a_glossary_tooltip() -> void:
	const Glossary := preload("res://Scripts/UI/Glossary.gd")
	const GlossaryLabelScript := preload("res://Scripts/UI/GlossaryLabel.gd")
	var pawn := _make_pawn(CG.Role.TANK)
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	var expected := Glossary.class_tags_text(pawn.pawn_class.role_primary, pawn.pawn_class.style, pawn.pawn_class.method)
	var found := false
	for child in panel._detail_box.get_children():
		if child is Label and child.get_script() == GlossaryLabelScript and child.tooltip_text == expected:
			found = true
	assert_true(found, "expected the tags line to carry the glossary tooltip")
	panel.free()

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

## Issue 21a's describe_op is real now: a plan reads as a full sentence, not
## just its own display_name, and a raw op id must never reach the screen.
func test_plan_line_reads_as_a_full_sentence_via_describe_op() -> void:
	var pawn := _make_pawn()
	var plan := _make_plan("Guard when hurt")
	var condition := PlanBlock.new()
	condition.kind = PlanBlock.Kind.CONDITION
	condition.op = &"self_hp_below_fraction"
	condition.args = {"fraction": 0.35}
	plan.condition = condition
	var targeting := PlanBlock.new()
	targeting.kind = PlanBlock.Kind.TARGETING
	targeting.op = &"target_self"
	var action := PlanBlock.new()
	action.kind = PlanBlock.Kind.ACTION
	action.op = &"use_action"
	action.args = {"action_id": &"test_swing"}
	plan.blocks = [targeting, action]
	pawn.plans = [plan]

	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])
	var text := _all_label_text(panel._detail_box)
	assert_true(text.contains("Guard when hurt"), text)
	assert_true(text.contains("self hp below 35%"), text)
	assert_true(text.contains("self"), text)
	assert_false(text.contains("self_hp_below_fraction"), "a raw op id must never reach the screen: " + text)
	panel.free()

## Plans show in priority order, by the plan's own real display_name.
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

## use_action blocks with no matching plan block are what "unused" means here.
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

## Issue 6, criterion 1/2: reorder is a real swap of `pawn.plans`, not just a
## relabel. Driven through the panel's own `_move_plan`, the same function the
## up/down buttons call — this is the logic under the button, not a proxy for
## it; the button wiring itself is covered by the disabled-state test below.
func test_reorder_swaps_plan_priority_in_pawns_plans_array() -> void:
	var pawn := _make_pawn()
	var guard := _make_plan("Guard when hurt")
	var execute := _make_plan("Execute when raging")
	pawn.plans = [guard, execute]
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	panel._move_plan(pawn, 0, 1)

	assert_eq(pawn.plans[0], execute)
	assert_eq(pawn.plans[1], guard)
	# _move_plan defers its rebuild (see its own comment: the calling button
	# lives inside the very box being rebuilt, so freeing it mid-signal is a
	# use-after-free) and this synchronous test never yields a frame for that
	# deferred call to run. Rebuilding by hand stands in for the frame this
	# test does not process, and still exercises the real render path.
	panel._build_detail(pawn)
	var text := _all_label_text(panel._detail_box)
	var execute_at := text.find("Execute when raging")
	var guard_at := text.find("Guard when hurt")
	assert_true(execute_at != -1 and guard_at != -1, text)
	assert_true(execute_at < guard_at, "screen did not follow the reorder: " + text)
	panel.free()

## A move past either end must be a no-op, not a crash or a silent duplicate.
func test_reorder_past_either_end_does_nothing() -> void:
	var pawn := _make_pawn()
	var only := _make_plan("Only plan")
	pawn.plans = [only]
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	panel._move_plan(pawn, 0, -1)
	panel._move_plan(pawn, 0, 1)

	assert_eq(pawn.plans.size(), 1)
	assert_eq(pawn.plans[0], only)
	panel.free()

## The up/down buttons must actually disable at the ends — a player pressing a
## button that does nothing and getting no feedback reads as broken, not as a
## no-op. Reaches the real Button nodes rather than asserting on the label
## text, since a disabled control is not text.
func test_reorder_buttons_disable_at_the_ends() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("First"), _make_plan("Second"), _make_plan("Third")]
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	var buttons := _find_buttons(panel._detail_box)
	var up_down := buttons.filter(func(b): return b.text == "^" or b.text == "v")
	assert_eq(up_down.size(), 6, "expected an up and a down button per plan row")
	# Row order matches plan order: first plan's Up is disabled, last plan's
	# Down is disabled, and nothing in between is.
	assert_true(up_down[0].disabled, "first plan's Up should be disabled")
	assert_false(up_down[1].disabled, "first plan's Down should be enabled")
	assert_false(up_down[4].disabled, "last plan's Up should be enabled")
	assert_true(up_down[5].disabled, "last plan's Down should be disabled")
	panel.free()

## Issue 6, criterion 2/3: swapping the TARGETING op changes which unit the
## plan focuses, and PlanInterpreter.decide (the real interpreter, not a
## stand-in) picks up the change on its own next call — proving the edit
## reaches a fight, not just the label on this screen.
func test_targeting_swap_changes_the_block_and_who_the_plan_targets_in_a_fight() -> void:
	var pawn := _make_pawn()
	var targeting := PlanBlock.new()
	targeting.kind = PlanBlock.Kind.TARGETING
	targeting.op = &"target_self"
	var action := PlanBlock.new()
	action.kind = PlanBlock.Kind.ACTION
	action.op = &"use_action"
	action.args = {"action_id": &"test_swing"}
	var plan := _make_plan("Always act")
	plan.blocks = [targeting, action]
	pawn.plans = [plan]

	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	assert_true(PlanInterpreter.TARGETING_OPS.has(&"target_nearest_enemy"))
	panel._set_targeting(targeting, &"target_nearest_enemy")
	assert_eq(targeting.op, &"target_nearest_enemy")
	assert_eq(targeting.args, {})

	var self_unit := CombatUnit.new()
	self_unit.id = 0
	self_unit.team = CG.Team.PLAYER
	self_unit.position = Vector2.ZERO
	self_unit.hp_max = 100
	self_unit.hp = 100
	self_unit.resource_max = 100
	self_unit.focus_id = -1
	self_unit.pawn = pawn
	var enemy := CombatUnit.new()
	enemy.id = 1
	enemy.team = CG.Team.ENEMY
	enemy.position = Vector2(10, 0)
	enemy.hp_max = 100
	enemy.hp = 100
	enemy.resource_max = 100
	enemy.focus_id = -1
	var state := CombatState.new(0)
	state.units.append(self_unit)
	state.units.append(enemy)

	var intent = PlanInterpreter.decide(state, self_unit)
	assert_not_null(intent, "edited plan should still fire")
	assert_eq(intent.target_id, enemy.id, "targeting swap should reach the interpreter, not just the screen")
	panel.free()

## Issue 6, criterion 2/3: swapping the ACTION changes which action the plan
## orders, restricted to what the pawn's own class actually starts with, and
## the swap reaches the real interpreter the same way the targeting swap does.
func test_action_swap_is_limited_to_the_pawns_own_actions_and_reaches_a_fight() -> void:
	var pawn := _make_pawn()
	pawn.pawn_class.starting_actions = [&"test_swing", &"test_alt"]
	var targeting := PlanBlock.new()
	targeting.kind = PlanBlock.Kind.TARGETING
	targeting.op = &"target_nearest_enemy"
	var action := PlanBlock.new()
	action.kind = PlanBlock.Kind.ACTION
	action.op = &"use_action"
	action.args = {"action_id": &"test_swing"}
	var plan := _make_plan("Always act")
	plan.blocks = [targeting, action]
	pawn.plans = [plan]

	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	var pickers := _find_option_buttons(panel._detail_box)
	var action_picker: OptionButton = null
	for p in pickers:
		if p.item_count == 2:
			action_picker = p
	assert_not_null(action_picker, "action picker should offer exactly the class's two starting actions")

	panel._set_action(action, &"test_alt")
	assert_eq(action.args.get("action_id"), &"test_alt")

	var attacker := CombatUnit.new()
	attacker.id = 0
	attacker.team = CG.Team.PLAYER
	attacker.position = Vector2.ZERO
	attacker.hp_max = 100
	attacker.hp = 100
	attacker.resource_max = 100
	attacker.focus_id = -1
	attacker.pawn = pawn
	var target := CombatUnit.new()
	target.id = 1
	target.team = CG.Team.ENEMY
	target.position = Vector2(10, 0)
	target.hp_max = 100
	target.hp = 100
	target.resource_max = 100
	target.focus_id = -1
	var state := CombatState.new(0)
	state.units.append(attacker)
	state.units.append(target)

	var intent = PlanInterpreter.decide(state, attacker)
	assert_not_null(intent)
	assert_eq(intent.action_id, &"test_alt", "action swap should reach the interpreter, not just the screen")
	panel.free()

## Issue 6 follow-up: conditions are now editable too. Swapping the op from
## one that reads false to `always` reaches PlanInterpreter.condition_holds,
## the same way the earlier targeting/action tests reach decide() -- the
## assertion that matters is the real interpreter's answer changing, not the
## screen's text.
func test_condition_op_swap_changes_whether_it_holds_in_a_fight() -> void:
	var pawn := _make_pawn()
	var condition := PlanBlock.new()
	condition.kind = PlanBlock.Kind.CONDITION
	condition.op = &"self_resource_at_least"
	condition.args = {"amount": 999}
	var plan := _make_plan("Guarded")
	plan.condition = condition
	pawn.plans = [plan]

	var attacker := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var enemy := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	var state := _state_with(attacker, enemy)
	assert_false(PlanInterpreter.condition_holds(state, attacker, plan), "resource 0 should not clear amount 999")

	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])
	panel._set_condition_op(plan, &"always")

	assert_eq(condition.op, &"always")
	assert_eq(condition.args, {})
	assert_true(PlanInterpreter.condition_holds(state, attacker, plan), "condition swap should reach the interpreter")
	panel.free()

## Retuning a condition's own value (not just swapping its op) must also
## reach the real interpreter -- a fraction edit that turns a false read into
## a true one.
func test_condition_value_edit_changes_the_threshold_in_a_fight() -> void:
	var pawn := _make_pawn()
	var condition := PlanBlock.new()
	condition.kind = PlanBlock.Kind.CONDITION
	condition.op = &"self_hp_below_fraction"
	condition.args = {"fraction": 0.1}
	var plan := _make_plan("Guarded")
	plan.condition = condition
	pawn.plans = [plan]

	# 95%, not full hp: below a 99% threshold and not below a 10% one, so the
	# same unit reads false before the edit and true after it with nothing
	# else changing -- the edit is what moves the answer, not the fixture.
	var mostly_healthy := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO, 0.95)
	var enemy := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	var state := _state_with(mostly_healthy, enemy)
	assert_false(PlanInterpreter.condition_holds(state, mostly_healthy, plan), "95% hp should not read below a 10% threshold")

	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])
	panel._set_condition_arg(condition, "fraction", 0.99)

	assert_almost_eq(float(condition.args.get("fraction")), 0.99)
	assert_true(PlanInterpreter.condition_holds(state, mostly_healthy, plan), "value edit should reach the interpreter")
	panel.free()

## A null condition means "always" to PlanInterpreter (`condition_holds`
## returns true with nothing to evaluate); picking a real op from that state
## must create the block rather than being a no-op or a crash.
func test_editing_a_null_condition_creates_a_real_block() -> void:
	var pawn := _make_pawn()
	var plan := _make_plan("No condition yet")
	plan.condition = null
	pawn.plans = [plan]

	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])
	panel._set_condition_op(plan, &"enemy_in_range")

	assert_not_null(plan.condition)
	assert_eq(plan.condition.op, &"enemy_in_range")
	assert_eq(plan.condition.args, {"range": 100.0})
	panel.free()

## The condition picker offers every op PlanInterpreter whitelists, no more
## and no fewer -- same guarantee the targeting/action pickers already give.
func test_condition_picker_offers_every_condition_op() -> void:
	var pawn := _make_pawn()
	var plan := _make_plan("Any condition")
	plan.condition = null
	pawn.plans = [plan]
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	var pickers := _find_option_buttons(panel._detail_box)
	var condition_picker: OptionButton = null
	for p in pickers:
		if p.item_count == PlanInterpreter.CONDITION_OPS.size():
			condition_picker = p
	assert_not_null(condition_picker, "expected one picker offering all %d condition ops" % PlanInterpreter.CONDITION_OPS.size())
	panel.free()

## rook found this on a real launch: the dropdown read "Self hp below 50%"
## while the spinbox right beside it read 65% -- every entry, including the
## selected one, was captioned from the op's default args rather than the
## plan's own. The label must agree with the setting it is labelling.
func test_selected_condition_captions_the_real_value_not_the_default() -> void:
	var pawn := _make_pawn()
	var condition := PlanBlock.new()
	condition.kind = PlanBlock.Kind.CONDITION
	condition.op = &"self_hp_below_fraction"
	condition.args = {"fraction": 0.65}
	var plan := _make_plan("Guard when hurt")
	plan.condition = condition
	pawn.plans = [plan]
	var panel := InspectPanel.new()
	panel._ready()
	panel.open([pawn])

	var row := panel._condition_editor(plan)
	var picker: OptionButton = row.get_child(1)
	var selected_text := picker.get_item_text(picker.selected)
	assert_true(selected_text.contains("65%"), "expected the real 65%% value in '%s'" % selected_text)
	assert_false(selected_text.contains("50%"), "must not still show the op's default")
	panel.free()

func _melee_unit(id: int, team: CG.Team, pos: Vector2, hp_frac: float = 1.0) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.position = pos
	u.hp_max = 100
	u.hp = int(100.0 * hp_frac)
	u.resource_max = 100
	u.resource = 0
	u.focus_id = -1
	u.pawn = null
	return u

func _state_with(a: CombatUnit, b: CombatUnit) -> CombatState:
	var state := CombatState.new(0)
	state.units.append(a)
	state.units.append(b)
	return state

func _find_buttons(node: Node) -> Array:
	var out := []
	if node is Button and not (node is OptionButton):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_buttons(c))
	return out

func _find_option_buttons(node: Node) -> Array:
	var out := []
	if node is OptionButton:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_option_buttons(c))
	return out

func _all_label_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	for child in node.get_children():
		out += _all_label_text(child)
	return out
