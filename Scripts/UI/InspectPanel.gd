extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PlanInterpreter := preload("res://Scripts/Plans/PlanInterpreter.gd")
const DefaultBehavior := preload("res://Scripts/Plans/DefaultBehavior.gd")
const Balance := preload("res://Scripts/Content/Balance.gd")
const PlanScript := preload("res://Scripts/Core/Plan.gd")
const PlanBlockScript := preload("res://Scripts/Core/PlanBlock.gd")
const Glossary := preload("res://Scripts/UI/Glossary.gd")
const GlossaryLabelScript := preload("res://Scripts/UI/GlossaryLabel.gd")

## Issue 21b: look at your pawns between fights. A full-screen overlay added
## as a child of whichever screen opens it (PartySelect or BattleView's end
## banner) rather than a Main-routed screen, so opening it never loses that
## screen's state (an in-progress party selection, a just-finished fight).
##
## Issue 6: plans are now editable here, not just readable. A player can
## reorder a pawn's plans (priority order — the earliest plan whose condition
## holds is the one that fires, per PlanInterpreter), swap the targeting or
## the action inside a block, and swap or retune the plan's own condition —
## all picked from choices the pawn actually has: TARGETING from
## PlanInterpreter.TARGETING_OPS, ACTION from the pawn's own
## `starting_actions`, CONDITION from PlanInterpreter.CONDITION_OPS. All three
## are whitelisted consts PlanInterpreter already exposed for this — no change
## to Scripts/Core or Scripts/Plans was needed.
##
## Issue 95 / 96: a plan is now one row of blocks — skill, target, condition —
## rather than a sentence with a stack of labelled dropdowns underneath, and
## plans can be added and removed rather than only reordered. Every pawn also
## carries an immutable final row describing what it does when no plan of its
## own fires. See the block comments at `_plans_section` for the decisions.
##
## Each CONDITION op reads a differently-shaped argument: `always` reads
## nothing, `self_hp_below_fraction`/`ally_below_hp_fraction` read a 0-1
## `fraction`, `self_resource_at_least` reads an int `amount`,
## `enemy_in_range` reads a float `range`. That mapping is
## `PlanInterpreter.CONDITION_ARG_SHAPE` and it is read from there.
##
## It used to be a private copy in this file. Issue 22 added the public one and
## its comment there says it was "moved here from InspectPanel.gd" — it was
## copied, and this screen went on reading the stale copy, which never gained
## `ally_has_harmful_status` when that op was added. Harmless by luck (the
## lookup falls back to `{"kind": "none"}`, which is the right answer for that
## particular op), and the next condition op that does read an argument would
## have silently lost its value editor. The copy is gone; there is one table.
##
## Editing mutates the Plan/PlanBlock resources on the PawnData in place —
## the same instance PartySelect and BattleView already hold and hand to
## CombatState when a fight starts, so no new plumbing was needed to make a
## change stick.
##
## OWNER: kite (was pike).
##
## `ActionDef.description` is on the trunk, empty on every action so far —
## shows as "(no description yet)" below, correct and expected, not a bug.
## `PlanInterpreter.describe_op(op, args)` (teal's, issue 21a) landed after
## this screen first shipped with the plan's own `display_name` standing in
## for the block-by-block sentence; now wired to the real thing.

signal closed

const _TOUCH := Palette.TOUCH_TARGET_MIN

## What one new plan costs against `Balance.plan_block_budget`. A plan needs a
## target block and a skill block to do anything at all, and `Plan.block_count`
## counts exactly those two — the condition is not a block by that definition,
## which is why the condition chip in a row is free. That definition lives in
## `Scripts/Core/Plan.gd` and is not this screen's to change; the budget copy
## below says which of the three chips costs, rather than leaving the player to
## infer it from a number that moves by two.
const NEW_PLAN_BLOCK_COST := 2

## Issue 68: this screen is the plan editor. Hover covers reading a class now
## (glossary chips here, on the party cards, and the action descriptions below),
## so the heading no longer presents the screen as general class information.
const HEADING := "Edit your pawns' plans"

## The general "how to play", written once for the whole screen rather than
## repeated per class. Every fact in it used to live under each pawn's own
## plans heading. Kept to four sentences on purpose: it sits above the thing it
## explains, and a paragraph nobody finishes is worse than a shorter one.
const HOW_TO_PLAY := (
	"A pawn runs the first row whose condition holds, checked from the top down. " +
	"The last row is its fallback and always matches, so a pawn always does something. " +
	"Reorder rows with the arrows, change a block by picking from it, and add or remove rows " +
	"within the pawn's block budget. " +
	"Nothing is locked yet: every action and every block is available to every pawn this slice."
)

## How the three blocks share a row's width. Not equal thirds, because the
## three do not carry comparable strings: a skill is a name ("Guard", "Smite"),
## a target is a phrase ("the nearest ally with a harmful status"), and a
## condition may carry a SpinBox inside its own share as well as its text.
## Measured against the real captions at 1280 wide rather than picked: at even
## thirds, "The ally with the lowest hp" and "Self resource at least" both
## clipped mid-word on a real capture.
const SKILL_SHARE := 0.8
const TARGET_SHARE := 1.1
const CONDITION_SHARE := 1.4

var _pawns: Array[PawnData] = []
var _selected_index: int = 0

var _list_box: VBoxContainer = null
var _detail_box: VBoxContainer = null

func _ready() -> void:
	# set_anchors_preset (not used here) tries to *preserve the control's
	# current rect* when it recomputes offsets — and this node's rect is
	# still (0,0) the moment _ready() runs, since _ready() fires after
	# entering the tree but before any layout pass has given it a real
	# size. That "preserved" a zero-size rect: offsets came out as
	# (0, -viewport_width, 0, -viewport_height), which nets to zero size
	# again however the anchors are set. set_anchors_and_offsets_preset
	# resets the offsets to match the preset outright instead of trying to
	# keep the old (here, meaningless) rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var backdrop := ColorRect.new()
	backdrop.color = Palette.BACKGROUND
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_top", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_right", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_bottom", int(Palette.SPACE_L))
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(Palette.SPACE_M))
	margin.add_child(column)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", int(Palette.SPACE_M))
	column.add_child(top_row)

	var title := Label.new()
	title.text = HEADING
	title.add_theme_font_size_override("font_size", Palette.FONT_SIZE_HEADING)
	title.add_theme_color_override("font_color", Palette.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)

	var close_button := Button.new()
	close_button.text = "Back"
	close_button.custom_minimum_size = Vector2(0.0, _TOUCH)
	close_button.pressed.connect(close)
	top_row.add_child(close_button)

	# Issue 68: one general "how to play", once, at the top of the screen. It
	# replaces the per-class explanation that used to sit under every pawn's
	# own plans heading, which is the round-one note this closes ("not every
	# class needs a plans-in-priority-order section, there should be a general
	# how to play"). Nothing below this line repeats any of it.
	#
	# The availability sentence is folded in rather than dropped: issue 21's
	# criterion 4 wants "why does nothing look locked" answered on the screen,
	# and it is the same kind of fact as the rest of this paragraph.
	var how_to_play := Label.new()
	how_to_play.text = HOW_TO_PLAY
	how_to_play.autowrap_mode = TextServer.AUTOWRAP_WORD
	how_to_play.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	how_to_play.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(how_to_play)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(Palette.SPACE_L))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(220.0, 0.0)
	# Both scroll containers need their own vertical EXPAND_FILL: `body`
	# stretching to fill `column`'s remaining height does not, on its own,
	# stretch its *children* — a Control without this collapses to its
	# content's minimum size regardless of how much room its parent has.
	# Found by a real launch: the whole list/detail body rendered as nothing
	# at all, at any resolution, with only the static header visible.
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", int(Palette.SPACE_S))
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_list_box)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A ScrollContainer lets its child grow past its own width by default and
	# offers a horizontal scrollbar instead. Found on a real launch the moment
	# a plan became one row (issue 96): every plan row ran off the right edge,
	# the Remove button was off screen entirely, and the budget line was cut
	# mid-sentence -- all of it reachable only by scrolling sideways, which
	# nobody does. Disabled, so the row is given exactly the panel's width and
	# the chips share it. This is the whole reason the chips are
	# SIZE_EXPAND_FILL rather than sized to their own text.
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(detail_scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", int(Palette.SPACE_S))
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail_box)

func open(pawns: Array[PawnData]) -> void:
	_pawns = pawns
	_selected_index = 0
	visible = true
	_rebuild_list()
	_select(0)

func close() -> void:
	visible = false
	closed.emit()

## free() rather than queue_free(): this rebuild can run again (a second
## selection) before a deferred deletion would ever flush, which would leave
## stale nodes overlapping the new ones — found by a test that rebuilt and
## read the text back in the same call, with no frame in between to flush a
## queue_free().
func _rebuild_list() -> void:
	for child in _list_box.get_children():
		child.free()
	for i in _pawns.size():
		var pawn := _pawns[i]
		var button := Button.new()
		button.text = pawn.display_name
		button.custom_minimum_size = Vector2(0.0, _TOUCH)
		button.toggle_mode = true
		button.button_pressed = i == _selected_index
		button.pressed.connect(_select.bind(i))
		_list_box.add_child(button)

func _select(index: int) -> void:
	if index < 0 or index >= _pawns.size():
		return
	_selected_index = index
	for i in _list_box.get_child_count():
		_list_box.get_child(i).button_pressed = i == index
	_build_detail(_pawns[index])

## free(), not queue_free() — see _rebuild_list's comment, same reasoning.
func _build_detail(pawn: PawnData) -> void:
	for child in _detail_box.get_children():
		child.free()
	if pawn.pawn_class == null:
		_detail_box.add_child(_line(pawn.display_name, Palette.FONT_SIZE_HEADING, Palette.TEXT))
		_detail_box.add_child(_line("No class assigned.", Palette.FONT_SIZE_BODY, Palette.TEXT_DIM))
		return

	var cls := pawn.pawn_class
	_detail_box.add_child(_line(pawn.display_name, Palette.FONT_SIZE_HEADING, Palette.TEXT))
	# Hover-info-box system, phase 1: the same trio PartyCard already makes
	# hoverable, read through the one shared Glossary function so the two
	# screens' copy cannot drift apart.
	var tags_line := _line(
		"%s · %s" % [_role_text(cls.role_primary), _style_method_text(cls.style, cls.method)],
		Palette.FONT_SIZE_BODY, Palette.TEXT_DIM)
	tags_line.set_script(GlossaryLabelScript)
	# Set explicitly rather than left to GlossaryLabel's own _ready(): this
	# node is built while InspectPanel may not yet be inside a live tree (a
	# test calling _build_detail() without ever entering one), and _ready()
	# only fires on real tree entry — same reasoning PartyCard._ready() is
	# already called manually elsewhere in this file's own sibling screen.
	tags_line.mouse_filter = Control.MOUSE_FILTER_STOP
	tags_line.tooltip_text = Glossary.class_tags_text(cls.role_primary, cls.style, cls.method)
	_detail_box.add_child(tags_line)

	_detail_box.add_child(_section_header("Attributes"))
	var attrs := HBoxContainer.new()
	attrs.add_theme_constant_override("separation", int(Palette.SPACE_M))
	for a in [CG.Attribute.STR, CG.Attribute.DEX, CG.Attribute.AGI, CG.Attribute.CON,
			CG.Attribute.INT, CG.Attribute.ATN, CG.Attribute.WIS]:
		# Not _line(): its word-autowrap makes a Label report a near-zero
		# minimum width, so seven of them in one HBoxContainer render on
		# top of each other instead of side by side. Found on a real
		# launch — every attribute name overlapped into one garbled word.
		# These seven short chips never need to wrap.
		var chip := Label.new()
		chip.set_script(GlossaryLabelScript)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.text = "%s %d" % [CG.attribute_name(a), pawn.attribute(a)]
		chip.tooltip_text = Glossary.attribute_text(a)
		chip.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
		chip.add_theme_color_override("font_color", Palette.TEXT)
		attrs.add_child(chip)
	_detail_box.add_child(attrs)

	# Issue 68: was one full-width block per action, name over description --
	# five actions on a Priest, so a wall of ten lines above the thing this
	# screen is for. Now the same chip-with-a-tooltip shape the attributes row
	# above already uses and the party cards already use, because reading a
	# description is exactly what hover is for now.
	# Issue 100: the pawn's actions, not the class's. An action an item granted is
	# one this pawn can use and plan with, so leaving it out of this row would
	# have said the opposite of what the row beneath it now offers.
	var available := _available_actions(pawn)
	_detail_box.add_child(_section_header("Actions"))
	if available.is_empty():
		_detail_box.add_child(_line("No actions.", Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
	else:
		var actions_row := HBoxContainer.new()
		actions_row.add_theme_constant_override("separation", int(Palette.SPACE_M))
		for action_id in available:
			actions_row.add_child(_action_chip(action_id))
		_detail_box.add_child(actions_row)

	for control in _plans_section(pawn):
		_detail_box.add_child(control)

	var plan_action_ids := _actions_used_in_plans(pawn)
	var unused := available.filter(func(a): return not plan_action_ids.has(a))
	if not unused.is_empty():
		var names := unused.map(func(a): return _action_display_name(a))
		_detail_box.add_child(_line(
			"Also available, not called by any plan: %s (falls to default behaviour)." % ", ".join(names),
			Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))

func _actions_used_in_plans(pawn: PawnData) -> Array:
	var out := []
	for plan in pawn.plans:
		for block in plan.blocks:
			if block.op == &"use_action":
				out.append(block.args.get("action_id", &""))
	return out

## One action as a hoverable chip. Same construction as the attribute chips
## above, including the `mouse_filter` line: `Label`'s engine default is
## `IGNORE`, so a chip built this way and left at the default never receives
## hover at all and its tooltip is unreachable. That was PLAYTEST-NOTES-2 item
## 13 and it is the reason every new hoverable Label on this screen sets it
## explicitly rather than trusting `GlossaryLabel._ready()`, which does not fire
## for a panel built outside a live tree.
func _action_chip(action_id: StringName) -> Control:
	var chip := Label.new()
	chip.set_script(GlossaryLabelScript)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	var action := Registry.get_action(action_id)
	if action == null:
		chip.text = "%s (not registered)" % String(action_id).capitalize()
		chip.add_theme_color_override("font_color", Palette.HP_LOW)
		chip.tooltip_text = "This action is not in the registry, so nothing can use it."
		return chip
	chip.text = action.display_name
	chip.add_theme_color_override("font_color", Palette.TEXT)
	chip.tooltip_text = _action_description(action)
	return chip

## Missing text must read as "not written yet", never as a blank tooltip that
## looks broken. Every registered action has a real description today
## (Tests/test_content_classes.gd holds that), so this is the guard for the
## next one added, not a state on the screen now.
func _action_description(action) -> String:
	return action.description if action.description != "" else "(no description yet)"

func _action_display_name(action_id: StringName) -> String:
	var action := Registry.get_action(action_id)
	return action.display_name if action != null else String(action_id).capitalize()

## The whole plans section, as a flat list of controls the caller adds in
## order. Built as a list rather than one container so the section's parts stay
## individually testable and the detail column keeps one separation setting.
##
## Issue 96: a plan is a row of blocks, not a sentence with labelled dropdowns
## stacked under it. Three chips per row: **skill, then target, then
## condition.**
##
## The order was the implementer's call. Both were built and rendered before
## choosing — `Screenshots/wren_plan_blocks_cond_first_warrior.png` against
## `wren_plan_blocks_skill_first_warrior.png`, same pawn, same width — and
## skill-first won on both of the two things the issue said should outweigh
## taste:
##
## - **It survives a long row.** The condition is the only block that carries
##   an inline selector, so putting it last puts the variable-width block on
##   the end. In the condition-first capture the Warrior's own conditions
##   clipped mid-word ("Self hp below", "Self resource a") because the SpinBox
##   was eating the middle of the row; in the skill-first capture nothing
##   clips at the same width.
## - **It reads as a column.** Skill-first, the Warrior's first column is
##   Guard / Taunt / Directional Block / Execute — four different things, all
##   short. Condition-first it was Self hp below / Always / Always / Self
##   resource a: two rows identical, and none of the four saying what the pawn
##   does. Plans fire in priority order, so the column is what gets scanned.
##
## Issue 95: rows can be added and removed, against `plan_block_budget`, with
## the budget stated in numbers. Issue 96 again: the last row is the pawn's
## default behaviour, always present, never editable.
func _plans_section(pawn: PawnData) -> Array[Control]:
	var out: Array[Control] = []

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(Palette.SPACE_M))
	# Issue 68 / the round-one note: "Plans, in priority order" appeared on
	# every class's inspect, and the sentence explaining what priority order
	# means appeared under it every time. Both facts are general, both now sit
	# in HOW_TO_PLAY once, and what is left under this heading is the only part
	# that is actually about this pawn: its own budget, in its own numbers.
	var heading := _section_header("Plans")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(_add_plan_button(pawn))
	out.append(header)

	var used := _blocks_used(pawn)
	var budget := Balance.plan_block_budget(pawn)
	out.append(_line(
		"%d of %d plan blocks used, %d free. A target block and a skill block cost 1 each, so a new plan costs %d. A condition costs 0. The budget is this pawn's WIS." % [
			used, budget, maxi(0, budget - used), NEW_PLAN_BLOCK_COST],
		Palette.FONT_SIZE_SMALL, Palette.TEXT))

	for i in pawn.plans.size():
		out.append(_plan_row(pawn.plans[i], pawn, i))

	out.append(_line(
		"Fallback, always last and not yours to change:",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
	for row in _default_rows(pawn):
		out.append(row)
	return out

## Disabled rather than hidden when there is no room, and the reason is on the
## screen beside it — a button that silently does nothing is exactly the
## failure issue 95 names.
func _add_plan_button(pawn: PawnData) -> Button:
	var button := Button.new()
	button.text = "+ Add a plan"
	button.custom_minimum_size = Vector2(0.0, _TOUCH)
	var free_blocks := Balance.plan_block_budget(pawn) - _blocks_used(pawn)
	var actions := _available_actions(pawn)
	if actions.is_empty():
		button.disabled = true
		button.tooltip_text = "This pawn has no actions, so a plan would have nothing to call."
	elif free_blocks < NEW_PLAN_BLOCK_COST:
		button.disabled = true
		button.tooltip_text = "%d block free, and a plan costs %d. Remove a row to make room." % [
			maxi(0, free_blocks), NEW_PLAN_BLOCK_COST]
	else:
		button.pressed.connect(_add_plan.bind(pawn))
	return button

## Blocks this pawn has spent, by the same count `Balance.plan_block_budget`
## bounds and `PresetPlans.total_blocks` reports: `Plan.block_count()` summed.
## The default row is not counted — it is not something the player authored,
## and charging WIS for a floor everyone has would change what every WIS value
## is worth (issue 96's own instruction, agreed with).
func _blocks_used(pawn: PawnData) -> int:
	var total := 0
	for plan in pawn.plans:
		total += plan.block_count()
	return total

## One plan as a row of blocks. Rebuilds the whole detail panel on any change
## rather than patching one chip in place — plans are short and this screen is
## not on a hot path, so simplicity wins over an incremental update.
func _plan_row(plan, pawn: PawnData, index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Palette.SPACE_S))

	var number := _tag_label("%d." % (index + 1))
	number.custom_minimum_size = Vector2(24.0, 0.0)
	row.add_child(number)

	var up := Button.new()
	up.text = "^"
	up.custom_minimum_size = Vector2(_TOUCH, _TOUCH)
	up.disabled = index == 0
	up.pressed.connect(_move_plan.bind(pawn, index, -1))
	row.add_child(up)

	var down := Button.new()
	down.text = "v"
	down.custom_minimum_size = Vector2(_TOUCH, _TOUCH)
	down.disabled = index == pawn.plans.size() - 1
	down.pressed.connect(_move_plan.bind(pawn, index, 1))
	row.add_child(down)

	# Skill, then target, then condition. Two passes over `plan.blocks` rather
	# than one, because the row's order is a reading decision and the array's
	# order is the interpreter's execution order (targeting before action, so
	# focus moves before the action reads it) -- they are not the same fact and
	# reordering the array to suit the screen would change what a plan does.
	for block in plan.blocks:
		if block.kind == PlanBlockScript.Kind.ACTION and block.op == &"use_action":
			var skill := _action_picker(pawn, block)
			skill.size_flags_stretch_ratio = SKILL_SHARE
			row.add_child(skill)
	for block in plan.blocks:
		if block.kind == PlanBlockScript.Kind.TARGETING and PlanInterpreter.TARGETING_OPS.has(block.op):
			var target := _targeting_picker(pawn, block)
			target.size_flags_stretch_ratio = TARGET_SHARE
			row.add_child(target)
	row.add_child(_condition_editor(plan))

	var remove := Button.new()
	remove.text = "X"
	remove.custom_minimum_size = Vector2(_TOUCH, _TOUCH)
	remove.tooltip_text = "Remove this plan and give its %d blocks back." % plan.block_count()
	remove.pressed.connect(_remove_plan.bind(pawn, index))
	row.add_child(remove)
	return row

## A new plan is the smallest one that does anything: no condition (which
## `PlanInterpreter.condition_holds` reads as always), the nearest enemy, and
## the pawn's first action. It lands last so it cannot silently outrank a plan
## the player already tuned — a new row inserted at the top would change the
## behaviour of every plan under it at the moment of adding.
func _add_plan(pawn: PawnData) -> void:
	var actions := _available_actions(pawn)
	if actions.is_empty():
		return
	if Balance.plan_block_budget(pawn) - _blocks_used(pawn) < NEW_PLAN_BLOCK_COST:
		return
	var plan := PlanScript.new()
	plan.id = StringName("custom_plan_%d" % (pawn.plans.size() + 1))
	plan.display_name = "New plan"
	var targeting := PlanBlockScript.new()
	targeting.kind = PlanBlockScript.Kind.TARGETING
	targeting.op = _available_targetings(pawn)[0]
	var action := PlanBlockScript.new()
	action.kind = PlanBlockScript.Kind.ACTION
	action.op = &"use_action"
	action.args = {"action_id": actions[0]}
	plan.blocks = [targeting, action]
	pawn.plans.append(plan)
	call_deferred("_build_detail", pawn)

## Removing every plan is allowed and is no longer a state a player can reach
## without seeing what happens: the default row below the list is what the pawn
## falls back to, and it is on the screen the whole time.
func _remove_plan(pawn: PawnData, index: int) -> void:
	if index < 0 or index >= pawn.plans.size():
		return
	pawn.plans.remove_at(index)
	call_deferred("_build_detail", pawn)

# ---------------------------------------------------------------------------
# What a block offers
#
# Issue 96: "treat a block as a thing the pawn owns, not a menu entry" — the
# player wants blocks to be findable later, in a Library that is out of scope
# for one room. These three functions are that seam and the only place a
# picker learns what it may offer. Today they return the interpreter's full
# whitelists and the class's own actions, which is exactly the old behaviour;
# narrowing them to what a pawn has actually found is a change here and
# nowhere else. Every picker below goes through them rather than reading
# `TARGETING_OPS` / `starting_actions` directly.
# ---------------------------------------------------------------------------

func _available_conditions(_pawn: PawnData) -> Array:
	return PlanInterpreter.CONDITION_OPS

func _available_targetings(_pawn: PawnData) -> Array:
	return PlanInterpreter.TARGETING_OPS

## Issue 100: `Registry.actions_for_pawn`, not `pawn.pawn_class.starting_actions`.
##
## This one line is why equipment was untestable. `CombatSim._collect_player_actions`
## already unioned the class's actions with every equipped piece's
## `granted_actions`, so the fight knew a Warrior in plate could Directional
## Block; this screen asked a different question and answered `starting_actions`
## alone, so the block never appeared for the player to plan with. The action
## fired and could not be planned, which is #98's principle exactly backwards.
##
## Registry owns the answer now so neither caller does. Nothing narrows here:
## this returns a superset of what it returned before, and a pawn wearing
## nothing gets a byte-identical list.
func _available_actions(pawn: PawnData) -> Array:
	return Registry.actions_for_pawn(pawn)

## Swaps two plans' priority by index and redraws. `pawn.plans` is the same
## array PartySelect/BattleView hand into CombatState, so this is the whole
## edit — no separate "apply" step and nothing to serialize back.
##
## Rebuild is deferred, not immediate: the control calling this (an Up/Down
## button, or a picker in `_targeting_picker`/`_action_picker`) lives inside
## `_detail_box` itself, and `_build_detail` frees every child of
## `_detail_box` on rebuild. Freeing a node with `free()` while it is still
## partway through emitting its own `pressed`/`item_selected` signal is a use-
## after-free the engine warns loudly about — found by actually pressing the
## buttons, not by reading the code. `queue_free()` in `_build_detail` would
## fix it too, but would reopen the stale-node bug its own comment documents
## for the case a rebuild fires twice before a queued deletion flushes.
## Deferring the call, not the free, keeps both fixed at once: the signal
## finishes emitting on its own node first, then this runs on a clean frame.
func _move_plan(pawn: PawnData, index: int, delta: int) -> void:
	var target := index + delta
	if target < 0 or target >= pawn.plans.size():
		return
	var tmp = pawn.plans[index]
	pawn.plans[index] = pawn.plans[target]
	pawn.plans[target] = tmp
	call_deferred("_build_detail", pawn)

## A TARGETING block's choices are PlanInterpreter.TARGETING_OPS — the same
## whitelist decide() itself checks against, so nothing this picker can select
## is a value the interpreter would reject. None of those ops read `args`
## (checked against `_eval_targeting`), so swapping one clears args rather
## than carrying over a value that meant something to a different op.
func _targeting_picker(pawn: PawnData, block) -> Control:
	var ops := _available_targetings(pawn)
	var picker := _block_chip()
	var current := 0
	for i in ops.size():
		var op: StringName = ops[i]
		picker.add_item(_cap_first(PlanInterpreter.describe_op(op, {})))
		if op == block.op:
			current = i
	picker.selected = current
	_caption_tooltip(picker)
	picker.item_selected.connect(func(idx): _set_targeting(block, ops[idx]))
	return picker

## Deferred for the same reason as `_move_plan`: called from the picker's own
## `item_selected` signal, and a rebuild frees that same picker.
func _set_targeting(block, op: StringName) -> void:
	block.op = op
	block.args = {}
	call_deferred("_build_detail", _pawns[_selected_index])

## An ACTION block's choices are the pawn's own `starting_actions` — what it
## can actually do, not every action in the Registry. Empty is a real state
## (a class with no actions is not this slice's problem to invent one for)
## and is shown disabled rather than left looking broken.
func _action_picker(pawn: PawnData, block) -> Control:
	var picker := _block_chip()
	var choices := _available_actions(pawn)
	if choices.is_empty():
		picker.add_item("(no actions)")
		picker.disabled = true
		return picker
	var current_id: StringName = block.args.get("action_id", &"")
	var current := 0
	for i in choices.size():
		var action_id: StringName = choices[i]
		picker.add_item(_action_display_name(action_id))
		if action_id == current_id:
			current = i
	picker.selected = current
	# Not `_caption_tooltip`: for a skill the useful hover is what the skill
	# does, not a longer copy of the word already printed on the chip. Issue
	# 68's whole premise is that reading is hover's job now, and this is the
	# one chip on the row that has something to read.
	var chosen = Registry.get_action(choices[current])
	if chosen != null:
		picker.tooltip_text = "%s\n%s" % [chosen.display_name, _action_description(chosen)]
	else:
		_caption_tooltip(picker)
	picker.item_selected.connect(func(idx): _set_action(block, choices[idx]))
	return picker

## Deferred for the same reason as `_move_plan`.
func _set_action(block, action_id: StringName) -> void:
	block.args = {"action_id": action_id}
	call_deferred("_build_detail", _pawns[_selected_index])

## A plan's trigger: "when <condition>". `plan.condition == null` and a block
## whose op is `&"always"` mean the same thing to PlanInterpreter (see
## `condition_holds`), so a null condition is shown and edited exactly like an
## `always` block rather than as a separate "no condition yet" state — picking
## a real op from a null condition creates the block on the spot.
func _condition_editor(plan) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	# The condition is one block of three and has to claim a third of the row
	# like the other two. Without this the wrapper takes only its minimum width
	# -- which, once the chip inside stopped fitting to its longest item, was
	# the SpinBox and nothing else: the condition chip rendered as a bare
	# dropdown arrow with no text at all. Found on a real capture.
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_stretch_ratio = CONDITION_SHARE

	var current_op: StringName = plan.condition.op if plan.condition != null else &"always"
	var ops := _available_conditions(_pawns[_selected_index] if _selected_index < _pawns.size() else null)
	var picker := _block_chip()
	var current := 0
	for i in ops.size():
		var op: StringName = ops[i]
		# The selected entry has to read the plan's own live value, not the
		# op's default -- rook found this on a real launch: the dropdown read
		# "Self hp below 50%" while the spinbox beside it read 65%, because
		# every entry (including the current one) was captioned from
		# _default_condition_args regardless of what the condition was
		# actually set to. An unselected entry still previews its own
		# default, which is exactly what picking it sets (_set_condition_op
		# resets args to the default on swap), so only the current entry
		# needs the real args.
		var preview_args: Dictionary = plan.condition.args if op == current_op and plan.condition != null else _default_condition_args(op)
		picker.add_item(_cap_first(PlanInterpreter.describe_op(op, preview_args)))
		if op == current_op:
			current = i
	picker.selected = current
	_caption_tooltip(picker)
	picker.item_selected.connect(func(idx): _set_condition_op(plan, ops[idx]))
	row.add_child(picker)

	var shape: Dictionary = PlanInterpreter.CONDITION_ARG_SHAPE.get(current_op, {"kind": "none"})
	if shape.get("kind") != "none" and plan.condition != null:
		row.add_child(_condition_value_editor(plan.condition, shape))
	return row

func _default_condition_args(op: StringName) -> Dictionary:
	var shape: Dictionary = PlanInterpreter.CONDITION_ARG_SHAPE.get(op, {"kind": "none"})
	if shape.get("kind") == "none":
		return {}
	return {shape["key"]: shape["default"]}

## Deferred for the same reason as `_move_plan` — called from the picker's own
## `item_selected` signal, and a rebuild frees that same picker. Creates the
## PlanBlock on the spot when `plan.condition` was null; every other case just
## overwrites the existing one, args reset to the new op's own default rather
## than carried over from an op that meant something else by them.
func _set_condition_op(plan, op: StringName) -> void:
	if plan.condition == null:
		var block := PlanBlockScript.new()
		block.kind = PlanBlockScript.Kind.CONDITION
		plan.condition = block
	plan.condition.op = op
	plan.condition.args = _default_condition_args(op)
	call_deferred("_build_detail", _pawns[_selected_index])

## One SpinBox, shaped by `PlanInterpreter.CONDITION_ARG_SHAPE`, sitting inline
## in the row right after the condition chip it belongs to — issue 96 asks for
## the condition to read as an editable sentence with its selector in it, not
## as a separate labelled field underneath. "fraction" is the one case
## that does not store what it shows: the control reads and writes whole
## percent (0-100) because that is what `describe_op` prints, and it is
## rescaled to the 0.0-1.0 `PlanInterpreter` actually reads on the way out.
func _condition_value_editor(block, shape: Dictionary) -> Control:
	var spin := SpinBox.new()
	spin.custom_minimum_size = Vector2(96.0, _TOUCH)
	var key: String = shape["key"]
	if shape["kind"] == "fraction":
		spin.min_value = 0
		spin.max_value = 100
		spin.step = 5
		spin.suffix = "%"
		spin.value = roundf(float(block.args.get(key, shape["default"])) * 100.0)
		spin.value_changed.connect(func(v): _set_condition_arg(block, key, v / 100.0))
	else:
		spin.min_value = shape["min"]
		spin.max_value = shape["max"]
		spin.step = shape["step"]
		spin.value = float(block.args.get(key, shape["default"]))
		spin.value_changed.connect(func(v): _set_condition_arg(block, key, v if shape["kind"] == "range" else int(v)))
	return spin

## Deferred for the same reason as `_move_plan`.
func _set_condition_arg(block, key: String, value) -> void:
	block.args[key] = value
	call_deferred("_build_detail", _pawns[_selected_index])

## One editable block in a plan row. `SIZE_EXPAND_FILL` on all three chips
## rather than a fixed width: they share the row's width in proportion to the
## text they carry, which is what keeps a long condition from pushing the skill
## chip off the end.
func _block_chip() -> OptionButton:
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(0.0, _TOUCH)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Both of these, and neither is optional. `OptionButton.fit_to_longest_item`
	# defaults to true, which makes the control report a minimum width big
	# enough for its longest *unselected* entry -- so a row of three chips
	# reported a minimum width wider than the screen and ran off the right
	# edge, taking the Remove button with it, even with the container's
	# horizontal scrolling disabled. `clip_text` alone does not help: it
	# governs drawing, not minimum size. Found by looking at a real capture,
	# not from the code.
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	return picker

## Clipping is what stops one long block from pushing the others off the row,
## but a clipped chip has still lost a word. The full caption goes on the
## tooltip so nothing is unreadable, only abbreviated — the same hover the rest
## of this screen already uses. Called after `selected` is set, since that is
## what decides which caption is showing.
func _caption_tooltip(picker: OptionButton) -> void:
	if picker.selected >= 0:
		picker.tooltip_text = picker.get_item_text(picker.selected)

## A block in the immutable default row. A Label inside its own panel: clearly
## a block, clearly not one of yours, and not a dropdown that refuses to open
## (issue 96's build note). Not greyed either — TEXT, not TEXT_DIM, because
## this row is describing behaviour that really happens, not a disabled one.
func _fixed_chip(text: String) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.HP_BACK
	style.border_color = Palette.ARENA_EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = Palette.SPACE_S
	style.content_margin_right = Palette.SPACE_S
	style.content_margin_top = Palette.SPACE_XS
	style.content_margin_bottom = Palette.SPACE_XS
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", Palette.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(label)
	return panel

# ---------------------------------------------------------------------------
# The default row
#
# Issue 96: "every pawn gets an immutable final row: move into range, then
# basic attack", and "it has to match what actually happens — check what that
# code really does before writing the row's text."
#
# It does not match, in three ways, and the issue's own instruction is to
# describe reality and raise the difference rather than reword either one. All
# three are read out of `DefaultBehavior` here rather than restated, so the
# numbers on this screen cannot drift from the numbers in the simulation:
#
# 1. **A pawn with a real heal checks its allies first.** `_first_heal` picks
#    the first action with `heals` and `power_scale > 0.0`, and if any living
#    ally is at or below `HEAL_THRESHOLD_FRACTION` of max hp, that is what it
#    does — walking to the ally if it is out of range. Only the Priest has one
#    today, so only the Priest grows this row.
# 2. **A ranged pawn does not "move into range", it holds a band.** Closer than
#    `KITE_RANGE_FRACTION` of its own range and it backs away; further than
#    `RANGED_COMMIT_FRACTION` and it approaches; between the two it fires. This
#    is the mechanism behind PLAYTEST-NOTES-2 item 11, so a player reading this
#    row can now see the retreat rather than being surprised by it. An action
#    with `pull_distance > 0.0` never backs off, and that exception shows too.
# 3. **"The basic attack" is not what it picks.** `_choose_attack_action` takes
#    the first non-heal melee action and the first non-heal ranged action in
#    `starting_actions` order, then chooses between them by the target's
#    current distance; with only one of the two it uses that one whatever the
#    distance. That list order is why `warden_chain_toss` never fired and why
#    `geyser_spout` had to be moved to the front — so the row names the actual
#    action, from the actual rule, rather than a concept the code does not have.
#
# Target selection is the fourth thing this row states: a taunter in range wins
# over distance (`_nearest_taunter`), otherwise the nearest enemy.
# ---------------------------------------------------------------------------

func _default_rows(pawn: PawnData) -> Array[Control]:
	var out: Array[Control] = []
	var actions: Array[ActionDef] = []
	for id in _available_actions(pawn):
		var a: ActionDef = Registry.get_action(id)
		if a != null:
			actions.append(a)

	# Skill, target, condition — the same order as an editable row above, so
	# the column reads straight down.
	var heal := _default_heal_action(actions)
	if heal != null:
		out.append(_fixed_row([
			"Move into range, then %s" % heal.display_name,
			"That ally",
			"When an ally is at or below %d%% hp" % int(round(DefaultBehavior.HEAL_THRESHOLD_FRACTION * 100.0)),
		]))

	var melee := _default_attack_action(actions, false)
	var ranged := _default_attack_action(actions, true)
	var base := "Otherwise" if heal != null else "Always"
	var target_text := "The nearest enemy, or whoever is taunting"
	if melee == null and ranged == null:
		out.append(_fixed_row(["Nothing. This pawn has no attack", target_text, base]))
	elif melee != null and ranged != null:
		# The only case with two rows to choose between, and the cut is the
		# melee action's own commit distance, not MELEE_RANGE_THRESHOLD --
		# that constant only sorts actions into the two piles, it never
		# decides between them. No player class carries both today; The
		# Warden does, which is why this branch exists at all.
		var cut := int(melee.range_units * DefaultBehavior.MELEE_COMMIT_FRACTION)
		out.append(_fixed_row([melee.display_name, target_text, "%s, within %d units" % [base, cut]]))
		out.append(_fixed_row([_ranged_text(ranged), target_text, "Otherwise"]))
	elif melee != null:
		out.append(_fixed_row([_melee_text(melee), target_text, base]))
	else:
		out.append(_fixed_row([_ranged_text(ranged), target_text, base]))
	return out

func _melee_text(action: ActionDef) -> String:
	return "Close to within %d units, then %s" % [
		int(action.range_units * DefaultBehavior.MELEE_COMMIT_FRACTION), action.display_name]

func _ranged_text(action: ActionDef) -> String:
	var commit := int(action.range_units * DefaultBehavior.RANGED_COMMIT_FRACTION)
	if action.pull_distance > 0.0:
		return "Close to within %d units and never back off, then %s" % [commit, action.display_name]
	return "Hold between %d and %d units, then %s" % [
		int(action.range_units * DefaultBehavior.KITE_RANGE_FRACTION), commit, action.display_name]

## Mirrors `DefaultBehavior._first_heal`, including the `power_scale > 0.0`
## part: `geyser_cleanse` sets `heals` and restores nothing, and the fallback
## deliberately never reaches for it.
func _default_heal_action(actions: Array[ActionDef]) -> ActionDef:
	for a in actions:
		if a.heals and a.power_scale > 0.0:
			return a
	return null

## Mirrors the halves of `DefaultBehavior._choose_attack_action`: the first
## non-heal action on the requested side of `MELEE_RANGE_THRESHOLD`, in
## `starting_actions` order. A class with only one side gets that one at every
## distance, which is what `_first_non_heal` does there.
func _default_attack_action(actions: Array[ActionDef], want_ranged: bool) -> ActionDef:
	for a in actions:
		if a.heals:
			continue
		if (a.range_units > DefaultBehavior.MELEE_RANGE_THRESHOLD) == want_ranged:
			return a
	return null

func _fixed_row(texts: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Palette.SPACE_S))
	var spacer := Control.new()
	# Lines the fixed row's first chip up under the editable rows' first chip,
	# which sits after a number label and two reorder buttons.
	spacer.custom_minimum_size = Vector2(24.0 + 2.0 * _TOUCH + 3.0 * Palette.SPACE_S, 0.0)
	row.add_child(spacer)
	for i in texts.size():
		var chip := _fixed_chip(texts[i])
		# Same share as the editable row's condition block, so the two columns
		# line up down the screen instead of nearly lining up.
		chip.size_flags_stretch_ratio = [SKILL_SHARE, TARGET_SHARE, CONDITION_SHARE][i]
		row.add_child(chip)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(_TOUCH + Palette.SPACE_S, 0.0)
	row.add_child(pad)
	return row

func _cap_first(s: String) -> String:
	if s.is_empty():
		return s
	return s.substr(0, 1).to_upper() + s.substr(1)

func _section_header(text: String) -> Control:
	return _line(text, Palette.FONT_SIZE_BODY, Palette.TEXT)

func _line(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	return label

## A short fixed string sitting beside a SIZE_EXPAND_FILL control in an
## HBoxContainer -- the plan row's priority number today. `_line`'s autowrap
## makes a Label report a near-zero minimum width, the same bug already found
## and worked around for the Attributes chips above, so the container gives it
## ~0 width and the neighbour's text is drawn starting at the same x position.
##
## Issue 53 found this on a real launch when the prefixes were "Targeting:",
## "Action:" and "Condition:" and one of them rendered as "TaSelfting:"
## (Screenshots/sweep_inspect_plan_editor_*). Those three prefixes are gone --
## issue 96 made each block a chip that says its own value, so there is nothing
## left to label -- but the trap is a property of `_line`, not of those
## strings, and the number label sits in exactly the same position.
func _tag_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	return label

func _role_text(role: CG.Role) -> String:
	return String(CG.Role.keys()[role]).capitalize()

func _style_method_text(style: CG.Style, method: CG.Method) -> String:
	return "%s · %s" % [
		String(CG.Style.keys()[style]).capitalize(),
		String(CG.Method.keys()[method]).capitalize(),
	]
