extends "res://Tests/TestCase.gd"

const IntentScript := preload("res://Scripts/Core/Intent.gd")

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

func _make_pawn(role: CG.Role = CG.Role.DPS, wis: int = 8) -> PawnData:
	var cls := ClassDef.new()
	cls.id = &"test_class"
	cls.display_name = "Test Class"
	cls.role_primary = role
	cls.style = CG.Style.MELEE
	cls.method = CG.Method.MARTIAL
	cls.starting_actions = [&"test_swing"]
	# WIS is the plan block budget (Balance.plan_block_budget). Left at the
	# ClassDef default of 0 every fixture would sit permanently over budget and
	# every Add button would be disabled, which is a different screen from the
	# one most of these tests mean to exercise. The budget tests set it
	# themselves.
	cls.base_attributes = {CG.Attribute.WIS: wis}
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

## Issue 53 found the "Targeting:"/"Action:"/"Condition:" prefix labels
## overlapping their own pickers on a real launch ("TaSelfting:",
## Screenshots/sweep_inspect_plan_editor_*): `_line()`'s autowrap makes a Label
## report a near-zero minimum width beside a SIZE_EXPAND_FILL control.
func test_the_priority_number_label_does_not_autowrap() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("Always act")]
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	var row := panel._plan_row(pawn.plans[0], pawn, 0)
	var number: Label = row.get_child(0)
	assert_eq(number.text, "1.")
	assert_eq(number.autowrap_mode, TextServer.AUTOWRAP_OFF, "a short fixed prefix must not report a near-zero minimum width")
	row.free()
	panel.free()

## Issue 96: one row of blocks, not a sentence with labelled dropdowns stacked
## underneath. The structural claim is that the condition, target and skill
## controls are siblings in one HBoxContainer, and that no Label sits between
## them captioning them.
func test_a_plan_is_one_row_of_blocks_with_no_prefix_labels() -> void:
	var pawn := _make_pawn()
	var condition := PlanBlock.new()
	condition.kind = PlanBlock.Kind.CONDITION
	condition.op = &"self_hp_below_fraction"
	condition.args = {"fraction": 0.35}
	var targeting := PlanBlock.new()
	targeting.kind = PlanBlock.Kind.TARGETING
	targeting.op = &"target_self"
	var action := PlanBlock.new()
	action.kind = PlanBlock.Kind.ACTION
	action.op = &"use_action"
	action.args = {"action_id": &"test_swing"}
	var plan := _make_plan("Guard when hurt")
	plan.condition = condition
	plan.blocks = [targeting, action]
	pawn.plans = [plan]

	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	var row := panel._plan_row(plan, pawn, 0)
	assert_true(row is HBoxContainer, "a plan is one row")
	var chips := _find_option_buttons(row)
	assert_eq(chips.size(), 4, "condition, movement, target and skill, all in the one row")
	# The only Label in the row is the priority number. "Targeting:",
	# "Action:" and "Condition:" are gone.
	var labels := _labels_in(row)
	assert_eq(labels.size(), 1, "the only label left is the priority number, found: %s" % str(labels.map(func(l): return l.text)))
	assert_eq(labels[0].text, "1.")
	row.free()
	panel.free()

# ---------------------------------------------------------------------------
# Hover-info-box system, phase 1
# ---------------------------------------------------------------------------

func test_attribute_chips_carry_glossary_tooltips() -> void:
	const GlossaryLabelScript := preload("res://Scripts/UI/GlossaryLabel.gd")
	var pawn := _make_pawn()
	var panel := InspectPanel.create()
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
					# Label's engine default `mouse_filter` is IGNORE, so the tooltip
					# machinery never sees the mouse; a plain Control defaults to STOP.
					# Set explicitly rather than left to GlossaryLabel's `_ready()`,
					# which never fires in this offline construction.
					assert_eq(chip.mouse_filter, Control.MOUSE_FILTER_STOP, "a Label defaults to MOUSE_FILTER_IGNORE and would never receive hover at all")
	assert_true(found, "expected to find the STR chip")
	panel.free()

func test_class_tags_header_line_carries_a_glossary_tooltip() -> void:
	const GlossaryLabelScript := preload("res://Scripts/UI/GlossaryLabel.gd")
	var pawn := _make_pawn(CG.Role.TANK)
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	var expected := Glossary.class_tags_text(pawn.pawn_class.role_primary, pawn.pawn_class.style, pawn.pawn_class.method)
	var found := false
	for child in panel._detail_box.get_children():
		if child is Label and child.get_script() == GlossaryLabelScript and child.tooltip_text == expected:
			found = true
			assert_eq(child.mouse_filter, Control.MOUSE_FILTER_STOP, "same fix as the attribute chips -- a Label defaults to MOUSE_FILTER_IGNORE")
	assert_true(found, "expected the tags line to carry the glossary tooltip")
	panel.free()

## Real bug, found on a real launch: the list/detail scroll containers had no
## vertical size flags, so they collapsed to their content's minimum size
## regardless of how much room the panel actually had, and the whole body
## rendered as nothing. Asserted directly rather than only via a screenshot.
func test_list_and_detail_containers_expand_to_fill() -> void:
	var panel := InspectPanel.create()
	panel._ready()
	var list_scroll: Control = panel._list_box.get_parent()
	var detail_scroll: Control = panel._detail_box.get_parent()
	assert_eq(list_scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL)
	assert_eq(detail_scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL)
	panel.free()

func test_opens_hidden_and_becomes_visible_on_open() -> void:
	var panel := InspectPanel.create()
	panel._ready()
	assert_false(panel.visible)
	var pawn := _make_pawn()
	panel.open([pawn])
	assert_true(panel.visible)
	panel.free()

func test_close_hides_the_panel_and_emits_closed() -> void:
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([_make_pawn()])
	var emitted: Array = []
	panel.closed.connect(func(): emitted.append(true))
	panel.close()
	assert_false(panel.visible)
	assert_eq(emitted, [true])
	panel.free()

func test_detail_shows_the_selected_pawns_name_and_role() -> void:
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([_make_pawn(CG.Role.HEALER)])
	var text := _all_label_text(panel._detail_box)
	assert_true(text.contains("Test Pawn"), text)
	assert_true(text.contains("Healer"), text)
	assert_false(text.contains("_"), "no raw enum name should reach the screen: " + text)
	panel.free()

func test_switching_pawns_rebuilds_the_detail_panel() -> void:
	var panel := InspectPanel.create()
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
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([_make_pawn()])
	var text := _all_label_text(panel)
	assert_true(text.to_lower().contains("available"), text)
	panel.free()

## Issue 21a's describe_op still writes every chip's caption, so a raw op id
## must never reach the screen. Was `test_plan_line_reads_as_a_full_sentence_
## via_describe_op` and asserted against the sentence and the plan's own
## display_name; issue 96 replaced the sentence with the chips, and the plan's
## authored display_name is no longer drawn at all (the chips say what it
## does). Same guarantee, read off the controls that carry it now.
func test_plan_blocks_read_in_a_players_language_via_describe_op() -> void:
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

	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	var text := _selected_chip_text(panel._detail_box)
	assert_true(text.contains("Self hp below 35%"), text)
	assert_true(text.contains("Self"), text)
	assert_false(text.contains("self_hp_below_fraction"), "a raw op id must never reach the screen: " + text)
	assert_false(text.contains("target_self"), "a raw op id must never reach the screen: " + text)
	panel.free()

## Plans show in priority order. Read off the chips rather than the plan's own
## display_name, which issue 96 stopped drawing -- two plans distinguished by
## their conditions, in the order `pawn.plans` holds them.
func test_plans_list_in_priority_order() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_plan_with_condition("first", &"self_hp_below_fraction", {"fraction": 0.35}),
		_plan_with_condition("second", &"enemy_in_range", {"range": 45.0})]
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	var text := _selected_chip_text(panel._detail_box)
	var hurt_at := text.find("Self hp below 35%")
	var range_at := text.find("An enemy within 45 units")
	assert_true(hurt_at != -1 and range_at != -1, text)
	assert_true(hurt_at < range_at, "priority order not preserved: " + text)
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
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	var text := _all_label_text(panel._detail_box)
	assert_true(text.contains("not called by any plan"), text)
	panel.free()

## Missing description text must read as "not written yet", never as a blank
## tooltip that looks broken. Was asserted against `_action_line`, the
## name-over-description block issue 68 replaced with a hoverable chip; the
## guarantee is the same one and it now lives on the tooltip.
func test_an_empty_action_description_reads_as_pending_not_blank() -> void:
	const ActionDefScript := preload("res://Scripts/Core/ActionDef.gd")
	var panel := InspectPanel.create()
	panel._ready()
	var blank := ActionDefScript.new()
	blank.id = &"blank"
	blank.display_name = "Blank"
	blank.description = ""
	assert_eq(panel._action_description(blank), "(no description yet)")
	# The positive half, per #104: a real description is passed through
	# unchanged, so this cannot pass by the function returning a constant.
	var written := ActionDefScript.new()
	written.description = "Does a real thing."
	assert_eq(panel._action_description(written), "Does a real thing.")
	panel.free()

## An action id that is not registered must be visibly wrong on the chip, not
## silently absent.
func test_an_unregistered_action_chip_says_so() -> void:
	var panel := InspectPanel.create()
	panel._ready()
	var chip: Label = panel._action_chip(&"nonexistent_action")
	assert_true(chip.text.contains("not registered"), chip.text)
	assert_false(chip.tooltip_text.is_empty(), "an unusable action still needs to say why")
	chip.free()
	panel.free()

# ---------------------------------------------------------------------------
# Issue 68: narrow the screen to plan editing, now that hover covers reading
# ---------------------------------------------------------------------------

## The round-one note this closes: *"Plans, in priority order still appears on
## every class's inspect. The general how to play has never replaced it."*
##
## Both halves asserted together, per #104 -- "the per-class heading is gone"
func test_the_general_how_to_play_replaces_the_per_class_plans_explanation() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("only")]
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	var whole_screen := _all_label_text(panel)
	var per_pawn := _all_label_text(panel._detail_box)

	# Positive: the general copy exists, once, and it carries the priority
	# rule that used to be repeated under every class.
	assert_true(whole_screen.contains(InspectPanel.HOW_TO_PLAY), "the general how-to-play must be on the screen")
	assert_true(InspectPanel.HOW_TO_PLAY.to_lower().contains("first row"), "it has to actually explain priority order")
	# Negative: it is not repeated inside the per-pawn detail column, which is
	# the part that rebuilds per class.
	assert_false(per_pawn.contains(InspectPanel.HOW_TO_PLAY), "the general copy must not be repeated per class")
	assert_false(per_pawn.contains("in priority order"), "the per-class heading must not restate the general rule: " + per_pawn)
	# And the section itself is still there and still says whose budget it is.
	assert_true(per_pawn.contains("Plans"), per_pawn)
	assert_true(per_pawn.contains("plan blocks used"), per_pawn)
	panel.free()

## The heading reframes around editing rather than presenting the screen as
## general class information.
func test_the_heading_is_about_editing_not_inspecting() -> void:
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([_make_pawn()])
	var text := _all_label_text(panel)
	assert_true(text.contains(InspectPanel.HEADING), text)
	assert_true(InspectPanel.HEADING.to_lower().contains("plans"), "the heading must name what the screen is for")
	panel.free()

## Actions are read by hover now, like every other term on this screen. The
## assertion that matters is that the description is reachable, not that the
## wall of text is gone -- deleting the section entirely would also remove the
## wall and would lose the information.
func test_action_chips_carry_their_description_as_a_reachable_tooltip() -> void:
	const GlossaryLabelScript := preload("res://Scripts/UI/GlossaryLabel.gd")
	var pawn := PawnFactory.make_starter_pawn(&"priest", &"priest", "Priest")
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	# Issue 129: the chips are built from `_available_actions`, which is
	# `Registry.actions_for_pawn` -- class actions plus equipment grants. Walking
	# `starting_actions` instead checked a different list than the one on screen,
	# and it stopped agreeing the moment the Priest's Bolt moved onto the Staff.
	var checked := 0
	for action_id in Registry.actions_for_pawn(pawn):
		var action = Registry.get_action(action_id)
		assert_not_null(action, "fixture depends on real registered actions")
		var chip: Label = panel._action_chip(action_id)
		assert_eq(chip.text, action.display_name)
		assert_eq(chip.tooltip_text, action.description)
		assert_false(chip.tooltip_text.is_empty(), "%s has no description to read" % action_id)
		# PLAYTEST-NOTES-2 item 13: a Label defaults to MOUSE_FILTER_IGNORE and
		# would never receive hover at all, so the tooltip would be unreachable
		# and this whole change would move the description out of sight. That
		# is the eighth built-and-unreachable on this project and it is one
		# line.
		assert_eq(chip.mouse_filter, Control.MOUSE_FILTER_STOP)
		assert_eq(chip.get_script(), GlossaryLabelScript)
		chip.free()
		checked += 1
	assert_true(checked >= 5,
		"the Priest ships four actions of its own and a Staff granting a fifth; checked %d" % checked)
	panel.free()

## The skill chip inside a plan row is the other place an action is named, and
## it is the one a player is looking at while editing.
func test_the_skill_block_hover_says_what_the_skill_does() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior")
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	var action_block := PlanBlock.new()
	action_block.kind = PlanBlock.Kind.ACTION
	action_block.op = &"use_action"
	action_block.args = {"action_id": pawn.pawn_class.starting_actions[0]}
	var picker: OptionButton = panel._action_picker(pawn, action_block)
	var action = Registry.get_action(pawn.pawn_class.starting_actions[0])
	assert_not_null(action)
	assert_true(picker.tooltip_text.contains(action.description),
		"the skill block's hover must carry the description, got '%s'" % picker.tooltip_text)
	# Negative half: it is not just a longer copy of the caption already
	# printed on the chip, which is what the other two blocks get.
	assert_true(picker.tooltip_text.length() > action.display_name.length(),
		"the skill hover must say more than the chip already does")
	picker.free()
	panel.free()

## Issue 6, criterion 1/2: reorder is a real swap of `pawn.plans`, not just a
## relabel. Driven through the panel's own `_move_plan`, the same function the
## up/down buttons call — this is the logic under the button, not a proxy for
## it; the button wiring itself is covered by the disabled-state test below.
func test_reorder_swaps_plan_priority_in_pawns_plans_array() -> void:
	var pawn := _make_pawn()
	var guard := _plan_with_condition("guard", &"self_hp_below_fraction", {"fraction": 0.35})
	var execute := _plan_with_condition("execute", &"enemy_in_range", {"range": 45.0})
	pawn.plans = [guard, execute]
	var panel := InspectPanel.create()
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
	var text := _selected_chip_text(panel._detail_box)
	var execute_at := text.find("An enemy within 45 units")
	var guard_at := text.find("Self hp below 35%")
	assert_true(execute_at != -1 and guard_at != -1, text)
	assert_true(execute_at < guard_at, "screen did not follow the reorder: " + text)
	panel.free()

## A move past either end must be a no-op, not a crash or a silent duplicate.
func test_reorder_past_either_end_does_nothing() -> void:
	var pawn := _make_pawn()
	var only := _make_plan("Only plan")
	pawn.plans = [only]
	var panel := InspectPanel.create()
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
	var panel := InspectPanel.create()
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

	var panel := InspectPanel.create()
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

	var panel := InspectPanel.create()
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

	var panel := InspectPanel.create()
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

	var panel := InspectPanel.create()
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

	var panel := InspectPanel.create()
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
	var panel := InspectPanel.create()
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
func test_selected_condition_captions_the_real_value_not_the_default() -> void:
	var pawn := _make_pawn()
	var condition := PlanBlock.new()
	condition.kind = PlanBlock.Kind.CONDITION
	condition.op = &"self_hp_below_fraction"
	condition.args = {"fraction": 0.65}
	var plan := _make_plan("Guard when hurt")
	plan.condition = condition
	pawn.plans = [plan]
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	var row := panel._condition_editor(plan)
	var picker: OptionButton = row.get_child(0)
	var selected_text := picker.get_item_text(picker.selected)
	assert_true(selected_text.contains("65%"), "expected the real 65%% value in '%s'" % selected_text)
	assert_false(selected_text.contains("50%"), "must not still show the op's default")
	panel.free()

# ---------------------------------------------------------------------------
# Issue 95: add and remove plans, against the block budget
# ---------------------------------------------------------------------------

## The whole point of the issue: a pawn is no longer stuck with the number of
## plans its class shipped with, and the plan the button makes is one the real
## interpreter will run -- not a row that only exists on this screen.
func test_adding_a_plan_makes_one_the_interpreter_actually_fires() -> void:
	var pawn := _make_pawn()
	pawn.pawn_class.starting_actions = [&"test_swing"]
	pawn.plans = []

	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	panel._add_plan(pawn)

	assert_eq(pawn.plans.size(), 1)
	assert_eq(pawn.plans[0].block_count(), InspectPanel.NEW_PLAN_BLOCK_COST)

	var attacker := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	attacker.pawn = pawn
	var enemy := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	var state := _state_with(attacker, enemy)

	var intent = PlanInterpreter.decide(state, attacker)
	assert_not_null(intent, "an added plan must fire, not just appear")
	assert_eq(intent.action_id, &"test_swing")
	assert_eq(intent.target_id, enemy.id, "a new plan targets the nearest enemy")
	assert_eq(PlanInterpreter.last_error, "", "the added plan must use only whitelisted ops")
	panel.free()

## A new plan lands last so it cannot silently outrank a plan the player
## already tuned.
func test_an_added_plan_goes_last_in_priority() -> void:
	var pawn := _make_pawn()
	var existing := _plan_with_condition("existing", &"self_hp_below_fraction", {"fraction": 0.35})
	pawn.plans = [existing]
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	panel._add_plan(pawn)
	assert_eq(pawn.plans.size(), 2)
	assert_eq(pawn.plans[0], existing, "an existing plan must keep its priority")
	panel.free()

## The budget is a real limit, and the button says so rather than doing
## nothing. WIS 3 buys one two-block plan and leaves 1 free, which is less than
## a plan costs.
func test_add_is_refused_and_the_button_disabled_when_the_budget_is_spent() -> void:
	var pawn := _make_pawn(CG.Role.DPS, 3)
	pawn.plans = []
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	panel._add_plan(pawn)
	assert_eq(pawn.plans.size(), 1, "the first plan fits in a budget of 3")

	panel._build_detail(pawn)
	var add := _button_named(panel._detail_box, "+ Add a plan")
	assert_not_null(add, "the Add button must be on the screen")
	assert_true(add.disabled, "1 block free and a plan costs 2 -- the button must be disabled")
	assert_true(add.tooltip_text.contains("2"), "the reason must name the cost: '%s'" % add.tooltip_text)

	panel._add_plan(pawn)
	assert_eq(pawn.plans.size(), 1, "the guard must hold even if the function is called directly")
	panel.free()

## Negative half of the test above: with room, the button is live. A guard that
## refuses everything passes the test above and is useless.
func test_add_is_enabled_when_there_is_room() -> void:
	var pawn := _make_pawn(CG.Role.DPS, 8)
	pawn.plans = []
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	var add := _button_named(panel._detail_box, "+ Add a plan")
	assert_not_null(add)
	assert_false(add.disabled, "8 blocks free is room for a plan costing 2")
	panel.free()

func test_removing_a_plan_takes_it_out_and_gives_its_blocks_back() -> void:
	var pawn := _make_pawn(CG.Role.DPS, 4)
	pawn.plans = []
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	panel._add_plan(pawn)
	panel._add_plan(pawn)
	assert_eq(pawn.plans.size(), 2)
	assert_eq(panel._blocks_used(pawn), 4)

	panel._remove_plan(pawn, 0)
	assert_eq(pawn.plans.size(), 1)
	assert_eq(panel._blocks_used(pawn), 2, "the removed plan's blocks must come back")

	panel._build_detail(pawn)
	var add := _button_named(panel._detail_box, "+ Add a plan")
	assert_false(add.disabled, "removing a plan must make the Add button live again")
	panel.free()

## Removing everything is allowed. Issue 96 is why: the fallback is no longer
## invisible, it is the row underneath.
func test_removing_every_plan_is_allowed_and_the_default_row_remains() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("only")]
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	panel._remove_plan(pawn, 0)
	assert_eq(pawn.plans.size(), 0)
	panel._build_detail(pawn)
	assert_eq(panel._default_rows(pawn).size() > 0, true, "the default row must survive an empty plan list")
	panel.free()

## The player's standing copy rule: no qualitative words for scale. The budget
## has to be readable as numbers, and it has to move when the plans do.
func test_the_budget_is_shown_as_numbers_and_follows_an_edit() -> void:
	var pawn := _make_pawn(CG.Role.DPS, 6)
	pawn.plans = []
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	var before := _all_label_text(panel._detail_box)
	assert_true(before.contains("0 of 6 plan blocks used"), before)
	assert_true(before.contains("6 free"), before)

	panel._add_plan(pawn)
	panel._build_detail(pawn)
	var after := _all_label_text(panel._detail_box)
	assert_true(after.contains("2 of 6 plan blocks used"), after)
	assert_true(after.contains("4 free"), after)
	panel.free()

# ---------------------------------------------------------------------------
# Issue 269: a plan row the pawn can no longer pay for
# ---------------------------------------------------------------------------
#
# The player ruled that a budget which shrinks under a plan already written does
# not refuse the unequip -- the surplus rows go inert instead. `CLAUDE.md`'s
# binding principle is that a pawn never does anything the player cannot see in
# the plans of action, so an inert row that looks like a live one is the purest
# violation of it available. These assert the mark, its sentence, and that the
# controls on the row still work.
func _pawn_over_budget() -> PawnData:
	var pawn := _make_pawn(CG.Role.DPS, 8)
	pawn.plans = []
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	panel._add_plan(pawn)
	panel._add_plan(pawn)
	panel.free()
	# Two plans, two blocks each, and a budget of 3: the first row is paid for
	# and the second is one block past the end.
	pawn.pawn_class.base_attributes = {CG.Attribute.WIS: 3}
	return pawn

func test_a_row_past_the_budget_is_dimmed_and_the_rows_before_it_are_not() -> void:
	var pawn := _pawn_over_budget()
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	var paid := panel._plan_row(pawn.plans[0], pawn, 0, false)
	var inert := panel._plan_row(pawn.plans[1], pawn, 1, true)
	assert_eq(paid.modulate.a, 1.0, "a row inside the budget must be drawn at full strength")
	assert_true(inert.modulate.a < 1.0, "a row past the budget must be dimmed")
	assert_true(inert.modulate.a > 0.0, "and still visible -- dimmed, not hidden")
	paid.free()
	inert.free()
	panel.free()

## The sentence is the half that satisfies the principle. It has to carry why
## (both numbers, and that the stat is WIS) and what to do about it (both ways
## out), on the screen, under the row it is about.
func test_the_inert_row_says_why_and_what_to_do_about_it() -> void:
	var pawn := _pawn_over_budget()
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	var screen := _all_label_text(panel._detail_box)
	assert_true(screen.contains("needs 4 WIS, this pawn has 3"), "the mark must name both numbers: " + screen)
	assert_true(screen.contains("Equip WIS gear"), "and the way to raise the budget: " + screen)
	assert_true(screen.contains("remove a row"), "and the way to lower the cost: " + screen)
	assert_true(screen.contains("4 of 3 plan blocks used"), "the summary must not report this as 0 free: " + screen)
	assert_true(screen.contains("1 over"), screen)
	panel.free()

## The negative, and it is the one that matters most: a pawn inside its budget
## must carry no mark at all. A mark that is always on is furniture within
## minutes, and the real one then goes unread.
func test_a_pawn_inside_its_budget_carries_no_inert_mark() -> void:
	var pawn := _make_pawn(CG.Role.DPS, 8)
	pawn.plans = []
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	panel._add_plan(pawn)
	panel._build_detail(pawn)

	var screen := _all_label_text(panel._detail_box)
	assert_false(screen.contains("Inert"), "nothing is inert at 2 of 8 blocks: " + screen)
	assert_false(screen.contains("are inert"), "and the summary must not warn: " + screen)
	assert_true(screen.contains("6 free"), screen)
	var row := panel._plan_row(pawn.plans[0], pawn, 0, false)
	assert_eq(row.modulate.a, 1.0)
	row.free()
	panel.free()

## An inert row is the row the player most needs to delete, so dimming must not
## take its controls away. `modulate` fades; it does not disable.
func test_an_inert_row_can_still_be_removed() -> void:
	var pawn := _pawn_over_budget()
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	var row := panel._plan_row(pawn.plans[1], pawn, 1, true)
	var remove := _button_named(row, "X")
	assert_not_null(remove, "the inert row must keep its remove button")
	assert_false(remove.disabled, "and that button must still work")
	row.free()

	panel._remove_plan(pawn, 1)
	assert_eq(pawn.plans.size(), 1, "removing the inert row must bring the pawn back inside its budget")
	panel._build_detail(pawn)
	assert_false(_all_label_text(panel._detail_box).contains("Inert"), "and the mark must go with it")
	panel.free()

# ---------------------------------------------------------------------------
# Issue 96: the immutable default row
# ---------------------------------------------------------------------------

## The row exists, it is last, and it is not a control -- "immutable in the UI
## and it should look it, not a dropdown that refuses to open".
func test_the_default_row_is_last_and_carries_no_editable_control() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("mine")]
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])

	for row in panel._default_rows(pawn):
		assert_eq(_find_option_buttons(row).size(), 0, "the default row must carry no picker")
		assert_eq(_find_buttons(row).size(), 0, "the default row must carry no button")
	panel.free()

## Issue 96's build note, agreed with rather than decided quietly: the floor
## everyone has is not something a pawn spent WIS on.
func test_the_default_row_costs_no_block_budget() -> void:
	var pawn := _make_pawn()
	pawn.plans = []
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	assert_eq(panel._blocks_used(pawn), 0, "a pawn with no plans of its own has spent nothing")
	assert_true(panel._default_rows(pawn).size() > 0, "and still has a default row")
	panel.free()

## **The assertion that matters, and the one issue 96 asked for by name: the
## row has to match what actually happens.** For every real class, the action
## named in the default row is the action `DefaultBehavior` really returns for
## that pawn at that distance -- run through the real fallback, not compared
## against a second list typed in this file.
func test_the_default_row_names_the_action_default_behavior_really_picks() -> void:
	var panel := InspectPanel.create()
	panel._ready()
	for class_id in [&"abomination", &"geysermancer", &"priest", &"siege_master", &"warrior"]:
		var pawn := PawnFactory.make_starter_pawn(class_id, class_id, String(class_id))
		# No plans: the fallback is what decides, which is exactly what this
		# row describes. A pawn keeping its preset plans would mostly be
		# testing PlanInterpreter instead.
		pawn.plans = []
		panel.open([pawn])
		var row_text := ""
		for row in panel._default_rows(pawn):
			row_text += _all_label_text(row) + "\n"

		for distance in [30.0, 400.0]:
			var unit := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
			unit.pawn = pawn
			# Issue 129: `Registry.actions_for_pawn`, which is what
			# `CombatSim._collect_player_actions` builds a real unit from. This
			# read `pawn.pawn_class.starting_actions`, which was the same list
			# while a class owned its own basic attack and became a pawn holding
			# *nothing* once the attack moved onto the main-hand weapon. The row
			# under test was already right; the fixture was comparing it against
			# a unit the game never builds.
			unit.actions = Registry.actions_for_pawn(pawn)
			var enemy := _melee_unit(1, CG.Team.ENEMY, Vector2(distance, 0))
			var state := _state_with(unit, enemy)
			var intent = DefaultBehavior.decide(state, unit)
			if intent == null or intent.action_id == &"":
				continue
			var action = Registry.get_action(intent.action_id)
			assert_not_null(action, "%s: default behaviour ordered an unregistered action" % class_id)
			assert_true(row_text.contains(action.display_name),
				"%s at %d units really uses '%s', and the default row does not say so:\n%s" % [
					class_id, int(distance), action.display_name, row_text])
	panel.free()

## The Priest is the one class whose fallback checks its allies before it
## attacks, and the row has to show that branch rather than the player's
## shorter description of it. Asserted against the real thing: a Priest beside
## a badly hurt ally really heals.
func test_the_priest_default_row_shows_the_heal_branch_the_code_really_has() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"priest", &"priest", "Priest")
	pawn.plans = []
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	var rows := panel._default_rows(pawn)
	assert_eq(rows.size(), 2, "a class with a real heal has a heal branch and an attack branch")

	var priest := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	priest.pawn = pawn
	priest.actions = pawn.pawn_class.starting_actions
	priest.resource = 999
	var hurt_ally := _melee_unit(1, CG.Team.PLAYER, Vector2(10, 0), 0.2)
	var enemy := _melee_unit(2, CG.Team.ENEMY, Vector2(300, 0))
	var state := CombatState.new(0)
	state.units.append(priest)
	state.units.append(hurt_ally)
	state.units.append(enemy)

	var intent = DefaultBehavior.decide(state, priest)
	assert_not_null(intent)
	assert_eq(intent.target_id, hurt_ally.id, "the Priest fallback really does treat an ally first")
	var row_text := _all_label_text(rows[0])
	assert_true(row_text.contains("ally"), row_text)
	panel.free()

## The row's numbers are read out of DefaultBehavior's own constants rather
## than typed here, so the screen cannot drift from the simulation. Asserted
## the only way that means anything: against the constants themselves.
func test_the_default_row_reads_its_thresholds_from_default_behavior() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"siege_master", &"siege_master", "Siege Master")
	pawn.plans = []
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	var text := ""
	for row in panel._default_rows(pawn):
		text += _all_label_text(row)

	var shot = Registry.get_action(&"siege_master_shot")
	assert_not_null(shot)
	assert_true(shot.range_units > DefaultBehavior.MELEE_RANGE_THRESHOLD, "this fixture is only meaningful for a ranged action")
	var commit := int(shot.range_units * DefaultBehavior.RANGED_COMMIT_FRACTION)
	assert_true(text.contains(str(commit)), "expected the commit distance %d in:\n%s" % [commit, text])
	panel.free()

func _button_named(node: Node, text: String) -> Button:
	for b in _find_buttons(node):
		if b.text == text:
			return b
	return null

# ---------------------------------------------------------------------------
# Issue 155: the pause inspection says why a row is or is not firing
# ---------------------------------------------------------------------------

## THE DEFECT THIS FILE DID NOT HAVE A TEST FOR, and it was on the trunk.
func test_every_real_pawns_every_condition_has_a_control_on_the_screen() -> void:
	var checked := 0
	for class_id in Registry.all_class_ids():
		var pawn := PawnFactory.make_preset_pawn(class_id, class_id, String(class_id))
		var panel := InspectPanel.create()
		panel._ready()
		panel.open([pawn])
		var rows := _plan_rows(panel)
		assert_eq(rows.size(), pawn.plans.size(),
			"%s: %d rows on screen for %d plans" % [class_id, rows.size(), pawn.plans.size()])
		for i in rows.size():
			var plan = pawn.plans[i]
			if plan.condition == null:
				continue
			var shape: Dictionary = PlanInterpreter.CONDITION_ARG_SHAPE.get(plan.condition.op, {"kind": "none"})
			if shape.get("kind") == "none":
				continue
			var controls := _find_option_buttons(rows[i]).size() + _spin_boxes_in(rows[i]).size()
			# skill + target + condition op = 3 pickers, and the value editor is
			# the fourth control. Three means the value editor is missing.
			assert_true(controls >= 4,
				"%s plan %d (%s, %s) has no editor for its condition value" % [
					class_id, i + 1, plan.condition.op, shape.get("kind")])
			checked += 1
		panel.free()
	assert_true(checked > 0, "no real pawn has a condition that takes a value; this test measured nothing")

## And the status kind specifically, end to end: the control exists, it shows the
## status the plan is really on, and picking another one reaches the interpreter.
func test_a_status_condition_is_picked_and_the_pick_reaches_the_interpreter() -> void:
	var pawn := _make_pawn()
	var condition := PlanBlock.new()
	condition.kind = PlanBlock.Kind.CONDITION
	condition.op = &"enemy_has_status"
	condition.args = {"status": CG.Status.BURN}
	var plan := _make_plan("Blast the burning")
	plan.condition = condition
	pawn.plans = [plan]

	var burning := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	burning.statuses[CG.Status.POISON] = 999
	var watcher := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var state := _state_with(watcher, burning)
	assert_false(PlanInterpreter.condition_holds(state, watcher, plan),
		"nothing is burning, so the row must not hold before the edit")

	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	var row: Control = _plan_rows(panel)[0]
	var pickers := _find_option_buttons(row)
	var status_picker: OptionButton = null
	for p in pickers:
		if p.selected >= 0 and p.get_item_text(p.selected) == "Burn":
			status_picker = p
	assert_true(status_picker != null,
		"the status editor must show the status the plan is actually on, found: %s" % _selected_chip_text(row))

	panel._set_condition_arg(condition, "status", CG.Status.POISON)
	assert_true(PlanInterpreter.condition_holds(state, watcher, plan),
		"picking Poison must reach the interpreter, not just the label")
	panel.free()

## The live verdicts. `waiting` and `acting` have to be produced by two rows of
## the same pawn in the same state, or the assertion is passed by a panel that
## prints one word everywhere.
func test_a_live_fight_marks_the_row_that_acted_and_the_rows_that_are_waiting() -> void:
	var pawn := _make_pawn()
	var hurt := _make_plan("Only when badly hurt")
	var hurt_condition := PlanBlock.new()
	hurt_condition.kind = PlanBlock.Kind.CONDITION
	hurt_condition.op = &"self_hp_below_fraction"
	hurt_condition.args = {"fraction": 0.1}
	hurt.condition = hurt_condition
	var always := _make_plan("Always")
	pawn.plans = [hurt, always]

	var unit := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	unit.pawn = pawn
	var state := _state_with(unit, _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0)))
	var acted := CombatEvent.make(CG.EventKind.ACTION_START, 5)
	acted.source_id = 0
	acted.source_plan = always.id
	state.events.append(acted)

	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn], state)
	## Asserted per row rather than over the whole panel. **The whole-panel
	## version was written first and it was vacuous:** the sentence explaining
	## the verdicts contains every one of these words, so `text.contains("acting")`
	var rows := _plan_rows(panel)
	assert_true(_all_label_text(rows[0]).contains(InspectPanel.VERDICT_WAITING), "row 1 is the one waiting")
	assert_true(_all_label_text(rows[1]).contains(InspectPanel.VERDICT_ACTING), "row 2 is the one that acted")
	panel.free()

## The compulsion, which is the whole reason the sentinel exists: a taunted pawn
## must not read as the fallback deciding.
func test_a_taunted_pawn_marks_the_fallback_row_taunted_rather_than_acting() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("Always")]
	var unit := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	unit.pawn = pawn
	var state := _state_with(unit, _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0)))
	var compelled := CombatEvent.make(CG.EventKind.ACTION_START, 5)
	compelled.source_id = 0
	compelled.source_plan = IntentScript.COMPELLED
	state.events.append(compelled)

	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn], state)
	var fallback := _all_label_text(_fallback_header(panel))
	assert_true(fallback.contains(InspectPanel.VERDICT_TAUNTED), fallback)
	assert_false(fallback.contains(InspectPanel.VERDICT_ACTING),
		"a compulsion is not the fallback deciding: %s" % fallback)
	panel.free()

	## And the case the compulsion has to be told apart FROM, in the same state
	## with one field changed. Without this pair, "taunted" could be the only
	## word the fallback row ever prints and both assertions above would still
	## pass. 19.0% of everything a player's pawns do lands here.
	compelled.source_plan = &""
	var second := InspectPanel.create()
	second._ready()
	second.open([pawn], state)
	var fell_through := _all_label_text(_fallback_header(second))
	assert_true(fell_through.contains(InspectPanel.VERDICT_ACTING), fell_through)
	assert_false(fell_through.contains(InspectPanel.VERDICT_TAUNTED), fell_through)
	second.free()

## Issue 308, and it is 66% of the compulsion: a pawn still WALKING to its
## taunter emits no event at all, so the panel used to keep reporting the plan
## it ran before the taunt landed. The fixture is the defect's own shape -- an
## ordinary ACTION_START on the pawn's own row, plus the live status.
func test_a_taunted_pawn_still_walking_marks_no_plan_row_acting() -> void:
	var pawn := _make_pawn()
	var plan := _make_plan("Always")
	pawn.plans = [plan]
	var unit := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	unit.pawn = pawn
	var state := _state_with(unit, _melee_unit(1, CG.Team.ENEMY, Vector2(400, 0)))
	var acted := CombatEvent.make(CG.EventKind.ACTION_START, 5)
	acted.source_id = 0
	acted.source_plan = plan.id
	state.events.append(acted)

	var before := InspectPanel.create()
	before._ready()
	before.open([pawn], state)
	## The pair: untaunted, this same state must read `acting`, or the assertions
	## below are passed by a panel that never says the word.
	assert_true(_all_label_text(_plan_rows(before)[0]).contains(InspectPanel.VERDICT_ACTING),
		"untaunted, the row that acted must still say acting")
	before.free()

	unit.statuses[CG.Status.TAUNTED] = 900
	unit.status_magnitude[CG.Status.TAUNTED] = 1.0
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn], state)
	var row := _all_label_text(_plan_rows(panel)[0])
	assert_false(row.contains(InspectPanel.VERDICT_ACTING),
		"the simulation has taken control away from this pawn: %s" % row)
	var fallback := _all_label_text(_fallback_header(panel))
	assert_true(fallback.contains(InspectPanel.VERDICT_TAUNTED), fallback)
	panel.free()

## The quiet case. Opened between fights -- which is how `PartySelect` opens it,
## and how it has always been opened -- there is nothing live to report and the
## screen must say nothing rather than guess. A verdict on a screen with no
## fight behind it would be furniture within one session.
func test_between_fights_no_row_carries_a_verdict() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("Always")]
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	var text := _all_label_text(panel._detail_box)
	for word in [InspectPanel.VERDICT_ACTING, InspectPanel.VERDICT_READY,
			InspectPanel.VERDICT_WAITING, InspectPanel.VERDICT_TAUNTED]:
		assert_false(text.contains(word), "'%s' on a panel with no fight behind it: %s" % [word, text])
	panel.free()

## A plan row is the row carrying the Remove button; the fallback rows and the
## headings have none. Derived from the screen rather than from an index, so it
## still finds the rows if the section grows another heading.
func _plan_rows(panel) -> Array:
	var out := []
	for child in panel._detail_box.get_children():
		for b in _find_buttons(child):
			if b.text == "X":
				out.append(child)
				break
	return out

## The row carrying InspectPanel.DEFAULT_ROW_TITLE, which is where the default
## row's own verdict hangs.
func _fallback_header(panel) -> Node:
	for child in panel._detail_box.get_children():
		if _all_label_text(child).contains(InspectPanel.DEFAULT_ROW_TITLE):
			return child
	return null

func _spin_boxes_in(node: Node) -> Array:
	var out := []
	if node is SpinBox:
		out.append(node)
	for c in node.get_children():
		out.append_array(_spin_boxes_in(c))
	return out

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

## Direct children only: the claim is about what the row itself puts beside the
## chips, not about anything an engine control builds inside itself.
func _plan_with_condition(name: String, op: StringName, args: Dictionary) -> Plan:
	var plan := _make_plan(name)
	var condition := PlanBlock.new()
	condition.kind = PlanBlock.Kind.CONDITION
	condition.op = op
	condition.args = args
	plan.condition = condition
	return plan

## Every block chip's currently selected caption, which is what a player reads.
func _selected_chip_text(node: Node) -> String:
	var out := ""
	for picker in _find_option_buttons(node):
		if picker.selected >= 0:
			out += picker.get_item_text(picker.selected) + "\n"
	return out

func _labels_in(node: Node) -> Array:
	var out := []
	for c in node.get_children():
		if c is Label:
			out.append(c)
	return out

func _all_label_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	for child in node.get_children():
		out += _all_label_text(child)
	return out

## ---------------------------------------------------------------------------
## Issue 396: the party screen's copy of this editor

func _embedded_panel(pawn: PawnData) -> InspectPanel:
	var panel := InspectPanel.create()
	panel._ready()
	panel.embed()
	panel.show_pawn(pawn)
	return panel

## "Two of six columns per row render completely empty -- just a chevron."
func test_no_chip_can_render_as_a_bare_chevron() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("Always act")]
	var panel := _embedded_panel(pawn)
	for row in _plan_rows(panel):
		var chips := _find_option_buttons(row)
		assert_true(chips.size() > 0, "the row has chips to check")
		for chip in chips:
			assert_true(chip.custom_minimum_size.x >= InspectPanel.CHIP_MIN_WIDTH,
				"%s may shrink to a bare chevron" % chip.name)
	panel.free()

## The Plans screen's one-row shape is what issue 96 asked for and what the
## playtester called readable, so only the embedded copy wraps.
func test_the_row_stays_one_line_on_the_full_width_plans_screen() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("Always act")]
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	assert_true(panel._plan_row(pawn.plans[0], pawn, 0) is HBoxContainer,
		"the full-width screen is the known-good reference and must not change")
	panel.free()

## Embedded there is about 480px and the number, arrows and X take 168 of it.
func test_the_row_wraps_onto_two_lines_in_a_column() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("Always act")]
	var panel := _embedded_panel(pawn)
	var row: Control = _plan_rows(panel)[0]
	assert_true(row is VBoxContainer, "the chips need a line of their own in a column")
	assert_eq(row.get_child_count(), 2, "one line of controls, one of chips")
	var all_chips := _find_option_buttons(row).size()
	assert_true(all_chips > 0, "the fixture has chips to place")
	assert_eq(_find_option_buttons(row.get_child(0)).size(), 0,
		"no chip shares the line with the arrows")
	assert_eq(_find_option_buttons(row.get_child(1)).size(), all_chips,
		"every chip is on the second line")
	panel.free()

## Both lines still belong to one row: the X and the arrows must still act on it.
func test_the_wrapped_row_keeps_its_controls() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("A"), _make_plan("B")]
	var panel := _embedded_panel(pawn)
	var rows := _plan_rows(panel)
	assert_eq(rows.size(), 2)
	var texts := []
	for b in _find_buttons(rows[0]):
		texts.append(b.text)
	for want in ["^", "v", "X"]:
		assert_true(texts.has(want), "the wrapped row lost %s: %s" % [want, str(texts)])
	panel.free()

## Issue 396 moved the block-cost rules to hover in the narrow column; issue 590
## moved them there on the full-width screen too, where they were a second
## paragraph of the `HOW_TO_PLAY` four sentences above them.
func test_the_budget_rules_are_hover_on_both_widths() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("Always act")]
	var embedded := _embedded_panel(pawn)
	var full := InspectPanel.create()
	full._ready()
	full.open([pawn])

	var short := _budget_label(embedded)
	assert_true(short.text.contains("plan blocks used"), short.text)
	assert_false(short.text.contains("A condition costs 0"),
		"the rules are five wrapped lines here: " + short.text)
	assert_true(short.tooltip_text.contains("A condition costs 0"),
		"and they have to still be readable somewhere: " + short.tooltip_text)
	var wide := _budget_label(full)
	assert_false(wide.text.contains("A condition costs 0"),
		"the full-width screen prints the rules as a paragraph: " + wide.text)
	assert_true(wide.tooltip_text.contains("A condition costs 0"),
		"and then they are nowhere at all: " + wide.tooltip_text)
	embedded.free()
	full.free()

func _budget_label(panel) -> Label:
	for child in panel._detail_box.get_children():
		if child is Label and child.text.contains("plan blocks used"):
			return child
	return null

## Issue 396: six armor entries ran past the bottom of a 720px window.
func test_a_dropdown_is_capped_below_the_screen_it_opens_on() -> void:
	var control := Control.new()
	assert_true(AppTheme.popup_max_height(control) < 720,
		"a popup allowed the whole screen has nowhere to put its scrollbar")
	assert_true(AppTheme.popup_max_height(control) > 200,
		"and one capped too hard shows nothing")
	control.free()
