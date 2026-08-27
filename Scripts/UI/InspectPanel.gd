extends Control
class_name InspectPanel

const PlanScript := preload("res://Scripts/Core/Plan.gd")
const GlossaryLabelScript := preload("res://Scripts/UI/GlossaryLabel.gd")
const IntentScript := preload("res://Scripts/Core/Intent.gd")

## Look at your pawns, and edit their plans. A full-screen overlay added as a
## child of whichever screen opens it (PartySelect, or BattleView's end
## banner) rather than a Main-routed screen, so opening it never loses that
## screen's state.
signal closed

const _TOUCH := Palette.TOUCH_TARGET_MIN

## What one new plan costs against `Balance.plan_block_budget`. A plan needs a
## target block and a skill block to do anything at all, and `Plan.block_count`
const NEW_PLAN_BLOCK_COST := 2

## Issue 269: how far an over-budget plan row fades. Dim enough to read as "this
## one is not like the others" at a glance, light enough that every chip on it is
## still legible -- the player asked for dimmed and still visible, not hidden and
## not a bare icon, because a row nobody can read is a row nobody can fix.
const INERT_ROW_ALPHA := 0.45

## Issue 269, and the exact sentence matters more than the dimming does. A row
## the pawn cannot pay for stops firing, and `CLAUDE.md`'s binding principle is
## that a pawn never does anything the player cannot see in the plans of action
## -- so the mark has to carry **why** (the budget is WIS, and here are both
## numbers) and **what to do about it** (two ways out, one per direction). Fading
## the row alone would say only that something is wrong with it.
const INERT_ROW_NOTE := "Inert: needs %d WIS, this pawn has %d. Equip WIS gear or remove a row."

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
	"The last row is its default and always matches, so a pawn always does something. " +
	"Reorder rows with the arrows, change a block by picking from it, and add or remove rows " +
	"within the pawn's block budget. " +
	"Library offers this class's ready-made rows; + Add a plan starts a blank one. " +
	"Nothing is locked yet: every action and every block is available to every pawn this slice."
)

## The same word the log's tag uses, so a player who reads "[default]" in the
## log can find the row it names on this screen (issue 441).
const DEFAULT_ROW_TITLE := "This pawn's default, always last and not yours to change:"

## How the three blocks share a row's width. Not equal thirds, because the
## three do not carry comparable strings: a skill is a name ("Guard", "Smite"),
## a target is a phrase ("the nearest ally with a harmful status"), and a
## condition may carry a SpinBox inside its own share as well as its text.
const SKILL_SHARE := 0.8
const TARGET_SHARE := 1.1
const CONDITION_SHARE := 1.4
## Issue 386, and it is the narrowest share on the row on purpose: a fourth
## block shrinks the other three, and the condition is the one that had least
## room to give. A block carrying a SpinBox gets the condition's share instead:
## a fixed 96px control inside a 0.8 share clipped "Hold 120 units from the
## target" down to the letter H on a real capture.
const MOVEMENT_SHARE := 0.8
const MOVEMENT_WITH_VALUE_SHARE := CONDITION_SHARE

var _pawns: Array[PawnData] = []
var _selected_index: int = 0

var _list_box: VBoxContainer = null
var _detail_box: VBoxContainer = null

## Issue 155. The fight this panel was opened over, or null when there is none.
var _live_state = null

## The tree this screen is made of lives in `Scenes/InspectPanel.tscn`, so that
## the player can open it in the editor and see the shape. **`new()` gives a
## bare `Control` with none of it** -- always `create()`.
static func create() -> InspectPanel:
	return (load("res://Scenes/InspectPanel.tscn") as PackedScene).instantiate()

## Everything a `.tscn` cannot say. Two kinds only:
func _ready() -> void:
	theme = AppTheme.shared()
	%Backdrop.color = Palette.BACKGROUND
	for side in ["left", "top", "right", "bottom"]:
		%Margin.add_theme_constant_override("margin_" + side, int(Palette.SPACE_L))
	%Column.add_theme_constant_override("separation", int(Palette.SPACE_M))
	%TopRow.add_theme_constant_override("separation", int(Palette.SPACE_M))
	%Body.add_theme_constant_override("separation", int(Palette.SPACE_L))
	%Title.text = HEADING
	%Title.add_theme_font_size_override("font_size", Palette.FONT_SIZE_HEADING)
	%CloseButton.custom_minimum_size = Vector2(0.0, _TOUCH)
	%CloseButton.pressed.connect(close)
	%HowToPlay.text = HOW_TO_PLAY
	%HowToPlay.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	%HowToPlay.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_list_box = %ListBox
	_detail_box = %DetailBox

## Issue 155's second half, and the answer to that issue's volume question.
## `focus` is the pawn to land on. Without it the panel always opened on the
## party's first pawn, so the unit card's Plans button showed somebody else.
func open(pawns: Array[PawnData], state = null, focus: PawnData = null) -> void:
	_pawns = pawns
	_live_state = state
	_selected_index = index_of(pawns, focus)
	visible = true
	_rebuild_list()
	_select(_selected_index)

## By id, not by reference: a fight may be running pawns rebuilt from the same
## data. Missing or unknown lands on the first pawn, which is the old behaviour.
static func index_of(pawns: Array[PawnData], focus: PawnData) -> int:
	if focus == null:
		return 0
	for i in pawns.size():
		if pawns[i] != null and pawns[i].id == focus.id:
			return i
	return 0

func close() -> void:
	visible = false
	closed.emit()

## Issue 351. The same panel laid into a column of another screen rather than
## over the top of it: no backdrop, no Back button, and no pawn list, because
## the screen it sits in IS the pawn list.
var _embedded := false

func embed() -> void:
	_embedded = true
	visible = true
	%Backdrop.visible = false
	%CloseButton.visible = false
	%HowToPlay.visible = false
	_list_box.get_parent().visible = false
	%Margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		%Margin.add_theme_constant_override("margin_" + side, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

## One pawn, in place, with the title naming who is being edited. The button
## that used to open this said "Inspect classes" while the page said "Edit your
## pawns' plans"; embedded there is no button and no mismatch.
func show_pawn(pawn: PawnData, state = null) -> void:
	_pawns = [pawn] as Array[PawnData]
	_live_state = state
	_selected_index = 0
	_library_open = pawn.plans.is_empty()
	visible = true
	if _embedded:
		%Title.visible = false
	_build_detail(pawn)

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
	_library_open = _pawns[index].plans.is_empty()
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

	## Issue 343. Embedded, the Equipment panel forty pixels below this one
	## prints both of these WITH the gear in them, and two lists that disagree
	## teach a player to trust neither. Cutting them also lifts the first plan
	## row -- the thing this panel is for -- clear of the fold.
	var available := _available_actions(pawn)
	if not _embedded:
		_detail_box.add_child(_section_header("Attributes"))
		_detail_box.add_child(_attributes_row(pawn))
		# Issue 68: was one full-width block per action, name over description --
		# five actions on a Priest, so a wall of ten lines above the thing this
		# screen is for. Now the same chip-with-a-tooltip shape the attributes row
		# above already uses and the party cards already use, because reading a
		# description is exactly what hover is for now.
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
			if block is UseActionBlock:
				var used: ActionDef = (block as UseActionBlock).action
				if used != null:
					out.append(used.id)
	return out

## Not `_line()`: its word-autowrap makes a Label report a near-zero minimum
## width, so seven of them in one HBoxContainer render on top of each other
## instead of side by side. Found on a real launch -- every attribute name
## overlapped into one garbled word.
func _attributes_row(pawn: PawnData) -> Control:
	var attrs := HBoxContainer.new()
	attrs.add_theme_constant_override("separation", int(Palette.SPACE_M))
	for a in [CG.Attribute.STR, CG.Attribute.DEX, CG.Attribute.AGI, CG.Attribute.CON,
			CG.Attribute.INT, CG.Attribute.ATN, CG.Attribute.WIS]:
		var chip := Label.new()
		chip.set_script(GlossaryLabelScript)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		## Issue 131: a generated pawn's attributes are rolled off its class
		## baseline, so the chip shows the difference and not only the total.
		var base := pawn.pawn_class.attribute(a) if pawn.pawn_class != null else 0
		var delta := pawn.attribute(a) - base
		chip.text = "%s %d" % [CG.attribute_name(a), pawn.attribute(a)]
		if delta != 0:
			chip.text += " (%+d)" % delta
		chip.tooltip_text = Glossary.attribute_text(a)
		if delta != 0:
			chip.tooltip_text += "\n\nThis pawn rolled %+d on top of a %s baseline of %d." % [
				delta, pawn.pawn_class.display_name, base]
		chip.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
		attrs.add_child(chip)
	return attrs

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
	var action := ActionLibrary.get_action(action_id)
	if action == null:
		chip.text = "%s (not registered)" % String(action_id).capitalize()
		chip.add_theme_color_override("font_color", Palette.HP_LOW)
		chip.tooltip_text = "This action is not in the registry, so nothing can use it."
		return chip
	chip.text = action.display_name
	chip.tooltip_text = _action_description(action)
	return chip

## Missing text must read as "not written yet", never as a blank tooltip that
## looks broken. Every registered action has a real description today
## (Tests/test_content_classes.gd holds that), so this is the guard for the
## next one added, not a state on the screen now.
func _action_description(action) -> String:
	return action.description if action.description != "" else "(no description yet)"

func _action_display_name(action_id: StringName) -> String:
	var action := ActionLibrary.get_action(action_id)
	return action.display_name if action != null else String(action_id).capitalize()

## The whole plans section, as a flat list of controls the caller adds in
## order. Built as a list rather than one container so the section's parts stay
## individually testable and the detail column keeps one separation setting.
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
	## Issue 412, and the same split `_assemble_row` already makes: two buttons
	## and a heading do not fit the party screen's column, and "+ Add a plan"
	## rendered clipped on a real capture the moment the second one arrived.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(Palette.SPACE_M))
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_child(_library_button(pawn))
	buttons.add_child(_add_plan_button(pawn))
	if _embedded:
		var stack := VBoxContainer.new()
		stack.add_child(header)
		stack.add_child(buttons)
		out.append(stack)
	else:
		header.add_child(buttons)
		out.append(header)

	var used := _blocks_used(pawn)
	var budget := Balance.plan_block_budget(pawn)
	## Issue 269: the second half of the first sentence changes when the pawn is
	## over budget, because "0 free" is true and says nothing about the rows that
	## have gone inert underneath. Equipment can raise WIS now, so the budget can
	## fall again when the equipment comes off, and "0 free" would be the whole
	## report of it.
	var over := used - budget
	var standing := ("%d free" % maxi(0, budget - used)) if over <= 0 else ("%d over, so the last rows are inert" % over)
	## Issue 590: the rules are the counter's mouseover on both widths now, not
	## only in the party screen's narrow column. Full width they were a second
	## paragraph of `HOW_TO_PLAY`, four sentences above them on the same screen.
	var standing_line := "%d of %d plan blocks used, %s." % [used, budget, standing]
	var rules := "A target, a skill and a movement block cost 1 each, so a new plan costs %d and adding movement to one costs 1 more. A condition costs 0. The budget is this pawn's WIS, equipment included." % NEW_PLAN_BLOCK_COST
	var summary := _line(standing_line, Palette.FONT_SIZE_SMALL,
		Palette.TEXT if over <= 0 else Palette.HP_LOW)
	summary.set_script(GlossaryLabelScript)
	summary.mouse_filter = Control.MOUSE_FILTER_STOP
	summary.tooltip_text = rules
	out.append(summary)

	var banner := _taunt_banner(pawn)
	if banner != null:
		out.append(banner)

	## Issue 269. Rows are paid for in priority order, so the surplus is always at
	## the bottom, and **which rows those are is not decided here.**
	## `PlanInterpreter.active_plan_count` is the single definition, and the
	## interpreter's own loop stops at the same index -- so a row this screen draws
	## as inert is a row the pawn does not run, by construction rather than by two
	## implementations happening to agree. `spent` below is a display number only:
	var active := PlanInterpreter.active_plan_count(pawn)
	var spent := 0
	for i in pawn.plans.size():
		var plan = pawn.plans[i]
		spent += plan.block_count()
		var inert := i >= active
		out.append(_plan_row(plan, pawn, i, inert))
		if inert:
			out.append(_inert_note(spent, budget))

	for control in _library_section(pawn):
		out.append(control)

	var fallback_header := HBoxContainer.new()
	var fallback_title := _line(
		DEFAULT_ROW_TITLE,
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	## Autowrap with no share of the row wraps this to one word per line the
	## moment a verdict sits beside it (issue 308's screenshot).
	fallback_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fallback_header.add_child(fallback_title)
	var fallback_verdict := _live_fallback_verdict(pawn)
	if fallback_verdict != "":
		fallback_header.add_child(_verdict_label(fallback_verdict))
	out.append(fallback_header)
	for row in _default_rows(pawn):
		out.append(row)
	return out

## Issue 379. One banner over all five rows, not a mark per row: while TAUNTED
## the pawn's plans are not outranked, they are **not consulted**, so there is
## one fact here and it belongs to the whole block.
const TAUNT_BANNER_MARK := "Taunted by"
const TAUNT_BANNER := "%s %s for %s. None of the rows below are read while that lasts: this pawn moves into range and uses its default attack on the taunter."

## Who is compelling this pawn, in words. The taunter can be dead for a tick
## before the status clears, so it is named only when it is still there.
const TAUNT_BANNER_UNKNOWN := "something"

func _taunt_banner(pawn: PawnData) -> Control:
	var unit = _live_unit(pawn)
	if unit == null or not unit.has_status(CG.Status.TAUNTED):
		return null
	var taunter = _live_state.unit(int(unit.status_magnitude.get(CG.Status.TAUNTED, -1.0)))
	var who: String = taunter.display_name if taunter != null else TAUNT_BANNER_UNKNOWN
	var left := maxi(int(unit.statuses[CG.Status.TAUNTED]) - _live_state.tick, 0)
	var note := _line(TAUNT_BANNER % [TAUNT_BANNER_MARK, who,
		"%.1fs" % (float(left) / float(CG.TICKS_PER_SECOND))],
		Palette.FONT_SIZE_SMALL, Palette.HP_LOW)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return note

## The sentence under an inert row. Indented under the row it belongs to, in the
## warning colour rather than the dim one -- dim is what this screen uses for
## explanatory prose, and this is not prose, it is a state the player has to act
## on.
func _inert_note(needed: int, budget: int) -> Control:
	var indent := HBoxContainer.new()
	var gutter := Control.new()
	gutter.custom_minimum_size = Vector2(Palette.SPACE_M, 0.0)
	indent.add_child(gutter)
	var note := _line(INERT_ROW_NOTE % [needed, budget], Palette.FONT_SIZE_SMALL, Palette.HP_LOW)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	indent.add_child(note)
	return indent

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
func _blocks_used(pawn: PawnData) -> int:
	var total := 0
	for plan in pawn.plans:
		total += plan.block_count()
	return total

## One plan as a row of blocks. Rebuilds the whole detail panel on any change
## rather than patching one chip in place — plans are short and this screen is
## not on a hot path, so simplicity wins over an incremental update.
func _plan_row(plan, pawn: PawnData, index: int, inert: bool = false) -> Control:
	var handle := HBoxContainer.new()

	var number := _tag_label("%d." % (index + 1))
	number.custom_minimum_size = Vector2(24.0, 0.0)
	handle.add_child(number)

	## Issue 155. Same number the combat log prints ("plan 3"), same order, from
	## the same array -- so a player who reads a tag in the log can find the row.
	var verdict := _live_verdict(pawn, plan)
	if verdict != "":
		handle.add_child(_verdict_label(verdict))

	var up := Button.new()
	up.text = "^"
	up.custom_minimum_size = Vector2(_TOUCH, _TOUCH)
	up.disabled = index == 0
	up.pressed.connect(_move_plan.bind(pawn, index, -1))
	handle.add_child(up)

	var down := Button.new()
	down.text = "v"
	down.custom_minimum_size = Vector2(_TOUCH, _TOUCH)
	down.disabled = index == pawn.plans.size() - 1
	down.pressed.connect(_move_plan.bind(pawn, index, 1))
	handle.add_child(down)

	var chips := HBoxContainer.new()
	# Skill, then target, then condition. Two passes over `plan.blocks` rather
	# than one, because the row's order is a reading decision and the array's
	# order is the interpreter's execution order (targeting before action, so
	# focus moves before the action reads it) -- they are not the same fact and
	# reordering the array to suit the screen would change what a plan does.
	for block in plan.blocks:
		if block is UseActionBlock:
			var skill := _action_picker(pawn, block)
			skill.size_flags_stretch_ratio = SKILL_SHARE
			chips.add_child(skill)
	for block in plan.blocks:
		if block is TargetingBlock:
			var target := _targeting_picker(pawn, plan, block)
			target.size_flags_stretch_ratio = TARGET_SHARE
			chips.add_child(target)
	chips.add_child(_movement_editor(pawn, plan))
	chips.add_child(_condition_editor(plan))
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var remove := Button.new()
	remove.text = "X"
	remove.custom_minimum_size = Vector2(_TOUCH, _TOUCH)
	remove.tooltip_text = "Remove this plan and give its %d blocks back." % plan.block_count()
	remove.pressed.connect(_remove_plan.bind(pawn, index))

	var row := _assemble_row(handle, chips, remove)
	if inert:
		row.modulate = Color(1.0, 1.0, 1.0, INERT_ROW_ALPHA)
	return row

## Issue 396. Embedded in the party screen's middle column the row has about
## 480px, of which the number, the two arrows and the X take 168 -- so four
## chips got 50 to 90px each and two of six columns rendered as a bare chevron.
## The chips get their own line there, which is the only way they see a width
## comparable to the full-width Plans screen the playtester called readable.
func _assemble_row(handle: HBoxContainer, chips: HBoxContainer, remove: Button) -> Control:
	if not _embedded:
		var row := handle
		for chip in chips.get_children():
			chips.remove_child(chip)
			row.add_child(chip)
		chips.free()
		row.add_child(remove)
		return row

	var stack := VBoxContainer.new()
	var top := handle
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(remove)
	stack.add_child(top)

	var indented := HBoxContainer.new()
	var gutter := Control.new()
	gutter.custom_minimum_size = Vector2(24.0, 0.0)
	indented.add_child(gutter)
	indented.add_child(chips)
	stack.add_child(indented)
	return stack

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
	var targeting := BlockCatalog.targeting(_available_targetings(pawn)[0])
	var action := UseActionBlock.new()
	action.action = _resolve_pawn_action(pawn, actions[0])
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
# Issue 412: the library. A class ships with no rows, so without a door here
# fifteen starting actions are reachable only by composing them from blank
# pickers.
const LIBRARY_HEADING := "Library: ready-made rows for this class"
const LIBRARY_OPEN := "Library (%d)"
const LIBRARY_CLOSE := "Hide library"
const LIBRARY_EMPTY_STATE := "No plans yet. Take a ready-made row from the library below, or press + Add a plan to build one from blank."
const LIBRARY_EXHAUSTED := "Every row this class's library offers is already on this pawn."
const LIBRARY_NONE := "This class has no library rows."
const LIBRARY_ADD := "Add"
const LIBRARY_COST := "%d blocks"

## Issue 434. The list is read top-down and it is also priority order, and the
## Geysermancer's first row does nothing until a second row applies BURN, so
## each row says what it waits for and rows are taken in the order they are in.
const LIBRARY_NEEDS_MARK := "Waits for"
const LIBRARY_NEEDS_ROW := "Waits for %s. \"%s\" applies it, so take both, in this order."
const LIBRARY_NEEDS_ROWS := "Waits for %s. These rows apply it: %s. Take one of them too."
const LIBRARY_NEEDS_FIGHT := "Waits for %s to come from the fight. Nothing else here applies it."

## Why an Add is dead rather than silently refusing, the same rule the movement
## picker follows (issue 392).
const LIBRARY_NO_ROOM := "%d block(s) free, and this row costs %d. Remove a row, or raise this pawn's WIS."

## Open by default on a pawn with no rows: the empty state is where the screen
## has to teach, and it was showing nothing.
var _library_open := false

## The class's presets this pawn has not already taken, matched by plan id.
## `PresetPlans.for_class` builds fresh `Plan` objects on every call, so a row
## here is safe to append and then mutate.
func _library_rows(pawn: PawnData) -> Array[Plan]:
	if pawn.pawn_class == null:
		return []
	var taken := {}
	for p in pawn.plans:
		taken[p.id] = true
	var out: Array[Plan] = []
	for p in PresetPlans.for_class(pawn.pawn_class.id):
		if not taken.has(p.id):
			out.append(p)
	return out

func _library_button(pawn: PawnData) -> Button:
	var button := Button.new()
	var rows := _library_rows(pawn)
	button.custom_minimum_size = Vector2(0.0, _TOUCH)
	button.text = LIBRARY_CLOSE if _library_open else LIBRARY_OPEN % rows.size()
	if rows.is_empty():
		button.disabled = true
		button.tooltip_text = _library_empty_reason(pawn)
	else:
		button.tooltip_text = "Rows written for this class, added at the cost they would cost to build by hand."
		button.pressed.connect(_toggle_library.bind(pawn))
	return button

func _library_empty_reason(pawn: PawnData) -> String:
	if pawn.pawn_class == null or PresetPlans.for_class(pawn.pawn_class.id).is_empty():
		return LIBRARY_NONE
	return LIBRARY_EXHAUSTED

func _toggle_library(pawn: PawnData) -> void:
	_library_open = not _library_open
	call_deferred("_build_detail", pawn)

func _library_section(pawn: PawnData) -> Array[Control]:
	var out: Array[Control] = []
	if pawn.plans.is_empty():
		out.append(_line(LIBRARY_EMPTY_STATE, Palette.FONT_SIZE_SMALL, Palette.TEXT))
	if not _library_open:
		return out
	out.append(_section_header(LIBRARY_HEADING))
	var rows := _library_rows(pawn)
	if rows.is_empty():
		out.append(_line(_library_empty_reason(pawn), Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
		return out
	for plan in rows:
		out.append(_library_row(pawn, plan))
	return out

## One library row: what it would do, in the same words the editable row above
## prints, plus what it costs and a button to take it.
func _library_row(pawn: PawnData, plan) -> Control:
	var cost: int = plan.block_count()
	var free_blocks := Balance.plan_block_budget(pawn) - _blocks_used(pawn)

	var add := Button.new()
	add.text = LIBRARY_ADD
	add.custom_minimum_size = Vector2(_TOUCH * 1.6, _TOUCH)
	if free_blocks < cost:
		add.disabled = true
		add.tooltip_text = LIBRARY_NO_ROOM % [maxi(0, free_blocks), cost]
	else:
		add.tooltip_text = "Add \"%s\" as a new last row. It costs %d blocks." % [plan.display_name, cost]
		add.pressed.connect(_add_preset.bind(pawn, plan))

	var price := _tag_label(LIBRARY_COST % cost)
	var texts := _library_row_texts(plan)
	var row := _assemble_library_row(add, price, texts)
	if free_blocks < cost:
		row.modulate = Color(1.0, 1.0, 1.0, INERT_ROW_ALPHA)

	var note := _dependency_text(pawn, plan)
	if note == "":
		return row
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	stack.add_child(row)
	stack.add_child(_indented_note(note))
	return stack

## What this row is waiting for, from `PresetPlans.row_dependencies`: the
## status it needs and whether another row of this class applies it, which is
## the difference between a row that is inert on its own and one the fight
## feeds.
func _dependency_text(pawn: PawnData, plan) -> String:
	if pawn.pawn_class == null:
		return ""
	var deps := PresetPlans.row_dependencies(pawn.pawn_class.id)
	if not deps.has(plan.id):
		return ""
	var status: String = Glossary.status_name(deps[plan.id]["status"])
	var suppliers: Array = deps[plan.id]["supplied_by"]
	if suppliers.is_empty():
		return LIBRARY_NEEDS_FIGHT % status
	var names: Array[String] = []
	for id in suppliers:
		for other in PresetPlans.for_class(pawn.pawn_class.id):
			if other.id == id:
				names.append(other.display_name)
	if names.size() == 1:
		return LIBRARY_NEEDS_ROW % [status, names[0]]
	return LIBRARY_NEEDS_ROWS % [status, ", ".join(names)]

## Under the row it belongs to and inside the Add button's gutter, the same
## place the inert-row sentence sits.
func _indented_note(text: String) -> Control:
	var line := HBoxContainer.new()
	var gutter := Control.new()
	gutter.custom_minimum_size = Vector2(_TOUCH * 1.6, 0.0)
	line.add_child(gutter)
	var label := _line(text, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	return line

## Wide, the three columns line up with the editable rows above. Embedded they
## cannot: `_fixed_chip` autowraps, and in the party screen's column one row
## stood five lines tall and two of them filled the panel.
func _assemble_library_row(add: Button, price: Label, texts: Array[String]) -> Control:
	if not _embedded:
		var row := HBoxContainer.new()
		row.add_child(add)
		for i in texts.size():
			var chip := _fixed_chip(texts[i])
			chip.size_flags_stretch_ratio = [SKILL_SHARE, TARGET_SHARE, CONDITION_SHARE][i]
			row.add_child(chip)
		price.custom_minimum_size = Vector2(_TOUCH + Palette.SPACE_S, 0.0)
		row.add_child(price)
		return row

	var narrow := HBoxContainer.new()
	narrow.add_child(add)
	var sentence := _line(" · ".join(texts), Palette.FONT_SIZE_SMALL, Palette.TEXT)
	sentence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	narrow.add_child(sentence)
	narrow.add_child(price)
	return narrow

## Skill, target, condition -- the same three columns, in the same order, as an
## editable row and as the fallback row, so the screen reads straight down.
func _library_row_texts(plan) -> Array[String]:
	var skill := "Nothing"
	var target := "No target"
	for block in plan.blocks:
		if block is UseActionBlock:
			var row_action: ActionDef = (block as UseActionBlock).action
			skill = row_action.display_name if row_action != null else "nothing"
		elif block is TargetingBlock:
			target = _cap_first(block.describe())
		elif block is MovementBlock:
			skill = "%s, then %s" % [_cap_first(block.describe()), skill]
	var condition: ConditionBlock = plan.condition if plan.condition != null else AlwaysBlock.new()
	return [skill, target, _cap_first(condition.describe())] as Array[String]

## Takes the row as-is. It is charged exactly what its blocks total, which is
## what building the same row by hand charges -- no special case, or the budget
## stops being checkable.
func _add_preset(pawn: PawnData, plan) -> void:
	if Balance.plan_block_budget(pawn) - _blocks_used(pawn) < plan.block_count():
		return
	pawn.plans.append(plan)
	call_deferred("_build_detail", pawn)

# ---------------------------------------------------------------------------
# What a block offers: the only place a picker learns what it may offer.
#
# Today these return the catalog's full order and the class's own actions.
# Narrowing them to what a pawn has actually found is a change here and nowhere
# else, so every picker goes through them rather than reading `BlockCatalog` or
# `starting_actions` directly.
func _available_conditions(_pawn: PawnData) -> Array:
	return BlockCatalog.CONDITION_OPS

func _available_movements(_pawn: PawnData) -> Array:
	return BlockCatalog.MOVEMENT_OPS

func _available_targetings(_pawn: PawnData) -> Array:
	return BlockCatalog.TARGETING_OPS

## Issue 100: `ActionLibrary.actions_for_pawn`, not `pawn.pawn_class.starting_actions`.
func _available_actions(pawn: PawnData) -> Array:
	return ActionLibrary.actions_for_pawn(pawn)

## The `ActionDef` behind an id this pawn actually offers. Checked against the
## pawn's own class first -- carried as `ActionDef` since #628 -- so a fixture
## class never registered anywhere still resolves; equipment grants are the
## only case still Registry-backed, because `EquipmentDef.granted_actions` is
## still `Array[StringName]`.
func _resolve_pawn_action(pawn: PawnData, action_id: StringName) -> ActionDef:
	if pawn.pawn_class != null:
		for a in pawn.pawn_class.starting_actions:
			if a.id == action_id:
				return a
	return ActionLibrary.get_action(action_id)

## Swaps two plans' priority by index and redraws. `pawn.plans` is the same
## array PartySelect/BattleView hand into CombatState, so this is the whole
## edit — no separate "apply" step and nothing to serialize back.
func _move_plan(pawn: PawnData, index: int, delta: int) -> void:
	var target := index + delta
	if target < 0 or target >= pawn.plans.size():
		return
	var tmp = pawn.plans[index]
	pawn.plans[index] = pawn.plans[target]
	pawn.plans[target] = tmp
	call_deferred("_build_detail", pawn)

## A TARGETING block's choices are `BlockCatalog.TARGETING_OPS`, in the catalog's
## own order, so nothing this picker can select is a block the interpreter would
## reject -- the script it builds is the whitelist.
func _targeting_picker(pawn: PawnData, plan, block: TargetingBlock) -> Control:
	var ops := _available_targetings(pawn)
	var current_op := BlockCatalog.op_of(block)
	var picker := _block_chip()
	var current := 0
	for i in ops.size():
		var op: StringName = ops[i]
		# The block's own operands for the entry it is already on, the same
		# correction `_condition_editor` below carries and for the same reason:
		picker.add_item(_cap_first(block.describe() if op == current_op else BlockCatalog.targeting(op).describe()))
		if op == current_op:
			current = i
	picker.selected = current
	_caption_tooltip(picker)
	picker.item_selected.connect(func(idx): _set_targeting(plan, block, ops[idx]))
	return picker

## Deferred for the same reason as `_move_plan`: called from the picker's own
## `item_selected` signal, and a rebuild frees that same picker. Swapping the op
## swaps the block, in place, so the plan's execution order does not move.
func _set_targeting(plan, block: TargetingBlock, op: StringName) -> void:
	var index: int = plan.blocks.find(block)
	if index != -1:
		plan.blocks[index] = BlockCatalog.targeting(op)
	call_deferred("_build_detail", _pawns[_selected_index])

## An ACTION block's choices are the pawn's own `starting_actions` — what it
## can actually do, not every action in the Registry. Empty is a real state
## (a class with no actions is not this slice's problem to invent one for)
## and is shown disabled rather than left looking broken.
func _action_picker(pawn: PawnData, block: UseActionBlock) -> Control:
	var picker := _block_chip()
	var choices := _available_actions(pawn)
	if choices.is_empty():
		picker.add_item("(no actions)")
		picker.disabled = true
		return picker
	var current_id: StringName = block.action.id if block.action != null else &""
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
	var chosen = ActionLibrary.get_action(choices[current])
	if chosen != null:
		picker.tooltip_text = "%s\n%s" % [chosen.display_name, _action_description(chosen)]
	else:
		_caption_tooltip(picker)
	picker.item_selected.connect(func(idx): _set_action(block, choices[idx]))
	return picker

## Deferred for the same reason as `_move_plan`.
func _set_action(block: UseActionBlock, action_id: StringName) -> void:
	block.action = _resolve_pawn_action(_pawns[_selected_index], action_id)
	call_deferred("_build_detail", _pawns[_selected_index])

## Issue 386. `keep_distance` and `move_into_cover` were built, tested and
## correct, and no player could create either: nothing outside `CoverProbe` and
## the tests ever constructed a movement block, so where a pawn stood
## was `DefaultBehavior`'s to decide for every plan a player could write.
const NO_MOVEMENT := &""
const NO_MOVEMENT_CAPTION := "default movement"

## Why the picker is dead rather than silently doing nothing, which is issue
## 95's own failure.
const MOVEMENT_NO_ROOM := "No plan block free, and a movement block costs 1. Remove a row, or raise this pawn's WIS."

## The movement block on this plan, or null. There is at most one:
## `_run_blocks` keeps the last MOVEMENT block it walks past, so a second would
## be paid for and never read.
static func movement_block_of(plan):
	for block in plan.blocks:
		if block is MovementBlock:
			return block
	return null

## The row's movement chip. Never disabled for a plan that already carries a
## block, whatever the budget says: taking it off again is the way back under.
func _movement_picker(pawn: PawnData, plan) -> OptionButton:
	var block = movement_block_of(plan)
	var ops := _available_movements(pawn)
	var current_op := BlockCatalog.op_of(block)
	var picker := _block_chip()
	picker.add_item(NO_MOVEMENT_CAPTION)
	var current := 0
	for i in ops.size():
		var op: StringName = ops[i]
		picker.add_item(_cap_first(block.describe() if op == current_op else BlockCatalog.movement(op).describe()))
		if op == current_op:
			current = i + 1
	picker.selected = current
	_caption_tooltip(picker)
	if block == null and Balance.plan_block_budget(pawn) - _blocks_used(pawn) < 1:
		picker.disabled = true
		picker.tooltip_text = MOVEMENT_NO_ROOM
		return picker
	picker.item_selected.connect(func(idx): _set_movement(pawn, plan,
		NO_MOVEMENT if idx == 0 else ops[idx - 1]))
	return picker

## Deferred for the same reason as `_move_plan`. A swap replaces the block in
## place, so only going from none to some costs a block and only going back
## refunds one.
func _set_movement(pawn: PawnData, plan, op: StringName) -> void:
	var block = movement_block_of(plan)
	if op == NO_MOVEMENT:
		if block != null:
			plan.blocks.erase(block)
	elif block == null:
		plan.blocks.append(BlockCatalog.movement(op))
	else:
		plan.blocks[plan.blocks.find(block)] = BlockCatalog.movement(op)
	call_deferred("_build_detail", pawn)

## The chip plus its value editor, sharing the row the way the condition does.
func _movement_editor(pawn: PawnData, plan) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_movement_picker(pawn, plan))
	var block = movement_block_of(plan)
	var operands: Array[Dictionary] = []
	if block != null:
		operands = block.operands()
	row.size_flags_stretch_ratio = MOVEMENT_WITH_VALUE_SHARE if not operands.is_empty() else MOVEMENT_SHARE
	for p in operands:
		row.add_child(_operand_editor(block, p))
	return row

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

	var condition: ConditionBlock = plan.condition if plan.condition != null else AlwaysBlock.new()
	var current_op := BlockCatalog.op_of(condition)
	var ops := _available_conditions(_pawns[_selected_index] if _selected_index < _pawns.size() else null)
	var picker := _block_chip()
	var current := 0
	for i in ops.size():
		var op: StringName = ops[i]
		# The selected entry reads the plan's own live block; every other one
		# previews a fresh block of that op, which is exactly what picking it
		# builds. Captioning the current entry from a default too is how the
		# dropdown once read "Self hp below 50%" beside a spinbox reading 65%.
		picker.add_item(_cap_first(condition.describe() if op == current_op else BlockCatalog.condition(op).describe()))
		if op == current_op:
			current = i
	picker.selected = current
	_caption_tooltip(picker)
	picker.item_selected.connect(func(idx): _set_condition_op(plan, ops[idx]))
	row.add_child(picker)

	if plan.condition != null:
		for p in plan.condition.operands():
			row.add_child(_operand_editor(plan.condition, p))
	return row

## Deferred for the same reason as `_move_plan` — called from the picker's own
## `item_selected` signal, and a rebuild frees that same picker. Creates the
## PlanBlock on the spot when `plan.condition` was null; every other case just
## overwrites the existing one, args reset to the new op's own default rather
## than carried over from an op that meant something else by them.
func _set_condition_op(plan, op: StringName) -> void:
	plan.condition = BlockCatalog.condition(op)
	call_deferred("_build_detail", _pawns[_selected_index])

## One control per exported operand, sitting inline in the row right after the
## chip it belongs to -- issue 96 asks for the condition to read as an editable
## sentence with its selector in it, not as a labelled field underneath.
##
## Issue 640: the bounds come from the field's own `@export_range`, not from a
## hand-written shape table. A float bounded at 1.0 is a fraction, and it is the
## one case that does not store what it shows: the control reads and writes
## whole percent because that is what `describe()` prints.
func _operand_editor(block: PlanBlock, property: Dictionary) -> Control:
	var key: StringName = property["name"]
	if property["type"] == TYPE_INT and property["hint"] == PROPERTY_HINT_ENUM:
		return _status_operand_editor(block, key)
	var bounds := _range_of(property)
	var scale := 100.0 if _is_fraction(property) else 1.0
	var spin := SpinBox.new()
	spin.custom_minimum_size = Vector2(96.0, _TOUCH)
	spin.min_value = snappedf(bounds.x * scale, RANGE_PRECISION)
	spin.max_value = snappedf(bounds.y * scale, RANGE_PRECISION)
	spin.step = snappedf(bounds.z * scale, RANGE_PRECISION)
	if scale != 1.0:
		spin.suffix = "%"
	spin.value = roundf(float(block.get(key)) * scale) if scale != 1.0 else float(block.get(key))
	var to_int: bool = property["type"] == TYPE_INT
	spin.value_changed.connect(func(v): _set_operand(block, key, int(v) if to_int else v / scale))
	return spin

## `min,max,step` out of an `@export_range` hint string, snapped.
##
## The snap is not cosmetic. Reading "0.05" back off the hint gives
## 0.05000000074505806, so the percent step came out at 5.00000007 and a
## SpinBox snaps its own value to its step: the Warrior's 50% guard row drew as
## 50.0000007. Measured by `Tools/OperandEditorAudit.gd` against the shape table
## this replaced, which is the only reason it was caught.
func _range_of(property: Dictionary) -> Vector3:
	var parts := String(property["hint_string"]).split(",")
	if parts.size() < 3:
		return Vector3(0.0, 999.0, 1.0)
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

## A float operand whose ceiling is 1.0 is a share, and shares are shown as
## whole percent. Nothing else in the vocabulary is bounded that tightly.
func _is_fraction(property: Dictionary) -> bool:
	return property["type"] == TYPE_FLOAT and is_equal_approx(_range_of(property).y, 1.0)

## How exactly a bound off a hint string is taken. Every step in the block
## vocabulary is a whole unit or larger once shown, so a thousandth is far below
## anything authored and far above the 32-bit noise.
const RANGE_PRECISION := 0.001

## A status is picked, not counted. Names come from `CG.Status.keys()`, the same
## source `CombatLogView._status_name` and `PlanInterpreter.status_word` read,
## so the editor, the log and the plan sentence cannot call one status three
## different things.
func _status_operand_editor(block: PlanBlock, key: StringName) -> Control:
	## Issue 396: 140 fixed took a fifth of the party screen's row for a word as
	## short as "Burn", and the chip beside it paid for it in blank chevrons.
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(CHIP_MIN_WIDTH, _TOUCH)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	picker.clip_text = true
	AppTheme.keep_popup_on_screen(picker)
	var current := int(block.get(key))
	for i in CG.Status.keys().size():
		picker.add_item(String(CG.Status.keys()[i]).capitalize(), i)
		if i == current:
			picker.selected = picker.item_count - 1
	picker.item_selected.connect(func(idx): _set_operand(block, key, picker.get_item_id(idx)))
	return picker

## Deferred for the same reason as `_move_plan`. The key is a real property name
## off `get_property_list()`, so this cannot write an operand nothing reads.
func _set_operand(block: PlanBlock, key: StringName, value) -> void:
	block.set(key, value)
	call_deferred("_build_detail", _pawns[_selected_index])

## Issue 396: a chip narrower than this renders as a bare chevron with no text
## at all, which is two of the six columns the playtester read off the party
## screen. A share of the row is not a floor, so the floor is stated.
const CHIP_MIN_WIDTH := 72.0

## One editable block in a plan row. `SIZE_EXPAND_FILL` on all three chips
## rather than a fixed width: they share the row's width in proportion to the
## text they carry, which is what keeps a long condition from pushing the skill
## chip off the end.
func _block_chip() -> OptionButton:
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(CHIP_MIN_WIDTH, _TOUCH)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Both of these, and neither is optional. `OptionButton.fit_to_longest_item`
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	AppTheme.keep_popup_on_screen(picker)
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
	var style := UIArt.panel_style(&"inspect", Palette.HP_BACK, Palette.ARENA_EDGE, 1)
	if style is StyleBoxFlat:
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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(label)
	return panel

# ---------------------------------------------------------------------------
# The default row: what a pawn does when no plan of its own fires.
func _default_rows(pawn: PawnData) -> Array[Control]:
	var out: Array[Control] = []
	var actions: Array[ActionDef] = []
	for id in _available_actions(pawn):
		var a: ActionDef = ActionLibrary.get_action(id)
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

## Issue 544: the automatic back-off is gone, so the row no longer describes one.
func _ranged_text(action: ActionDef) -> String:
	return "Close to within %d units, then %s" % [
		int(action.range_units * DefaultBehavior.RANGED_COMMIT_FRACTION), action.display_name]

## Mirrors `DefaultBehavior._first_heal`, including the `power_scale > 0.0`
## part: `geyser_cleanse` sets `heals` and restores nothing, and the fallback
## deliberately never reaches for it.
func _default_heal_action(actions: Array[ActionDef]) -> ActionDef:
	for a in actions:
		if a.heals and a.power_scale > 0.0:
			return a
	return null

## Issue 129: `DefaultBehavior` itself, not a mirror of it.
func _default_attack_action(actions: Array[ActionDef], want_ranged: bool) -> ActionDef:
	return DefaultBehavior.default_attack_action(actions, want_ranged)

## Named so a probe and a test can find the rows the panel builds for itself.
const FALLBACK_ROW_NAME := "FallbackRow"

func _fixed_row(texts: Array) -> Control:
	if _embedded:
		return _narrow_fixed_row(texts)
	var row := HBoxContainer.new()
	row.name = FALLBACK_ROW_NAME
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

## Issue 414, and the same shape `_assemble_library_row` takes: in the party
## screen's column three autowrapping chips got 45, 69 and 91px and stood the
## row 187px tall, so the column says it in one line instead.
func _narrow_fixed_row(texts: Array) -> Control:
	var row := HBoxContainer.new()
	row.name = FALLBACK_ROW_NAME
	var gutter := Control.new()
	gutter.custom_minimum_size = Vector2(24.0, 0.0)
	row.add_child(gutter)
	var sentence := _line(" · ".join(texts), Palette.FONT_SIZE_SMALL, Palette.TEXT)
	sentence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sentence)
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

## A short fixed string beside a SIZE_EXPAND_FILL control in an HBoxContainer.
const VERDICT_ACTING := "acting"
const VERDICT_READY := "ready"
const VERDICT_WAITING := "waiting"
const VERDICT_TAUNTED := "taunted"
const VERDICT_HELD := "held"

## One word for one plan row, or "" when there is no live fight to read, and
## **none at all while the pawn is taunted**: `CombatSim._decide_phase` checks
## the compulsion before it calls the plan layer, so a `ready` beside a row is
## a claim about a row nothing consults. Issue 379.
func _live_verdict(pawn: PawnData, plan) -> String:
	var unit = _live_unit(pawn)
	if unit == null:
		return ""
	if unit.has_status(CG.Status.TAUNTED):
		return ""
	if _last_source_plan(unit) == plan.id:
		return VERDICT_ACTING
	if not PlanInterpreter.condition_holds(_live_state, unit, plan):
		return VERDICT_WAITING
	## Issue 575: a busy pawn reads no row at all until its action ends, so
	## `ready` beside one is a claim about a row nothing is consulting.
	return VERDICT_HELD if unit.is_busy() else VERDICT_READY

## The same, for the immutable fallback row. It has no condition to hold, so it
## is either what the pawn is doing or it is not -- and the compulsion gets its
## own word, because a taunted pawn is not falling back, it is being overruled.
func _live_fallback_verdict(pawn: PawnData) -> String:
	var unit = _live_unit(pawn)
	if unit == null:
		return ""
	## The live status first: a compelled walk emits no event, so two thirds of
	## the compulsion is invisible to the event stream (issue 308).
	if unit.has_status(CG.Status.TAUNTED):
		return VERDICT_TAUNTED
	var last := _last_source_plan(unit)
	if last == IntentScript.COMPELLED:
		return VERDICT_TAUNTED
	return VERDICT_ACTING if last == &"" else ""

## The plan behind this unit's most recent decision, read off the event stream
## rather than off the unit. `CombatUnit.intent` is created and consumed inside
## one `step()` and is null by the time anything can look at it -- rule 2 on the
## board, "X never happens is also passed by X can never be observed" -- so
## ACTION_START is the only place the answer survives.
func _last_source_plan(unit) -> StringName:
	var events = _live_state.events
	for i in range(events.size() - 1, -1, -1):
		var e = events[i]
		if e.kind == CG.EventKind.ACTION_START and e.source_id == unit.id:
			return e.source_plan
	return &""

## The fighting unit built from this PawnData, or null. Matched on the PawnData
## instance, which `CombatSim.build` stores on the unit -- the same instance
## this panel edits, so a pawn cannot be confused with another of the same class.
func _live_unit(pawn: PawnData):
	if _live_state == null:
		return null
	for u in _live_state.units:
		if u.pawn == pawn:
			return u
	return null

## Issue 590: what each verdict word means, on the word itself. It was a
## standing key sentence over the rows, which is explainer text beside the thing
## it explains rather than on it.
const VERDICT_HELP := {
	VERDICT_ACTING: "This row chose what the pawn last did.",
	VERDICT_READY: "This row's condition holds and the pawn is free to take it. If it is not the row acting, a row above it won or its skill could not fire.",
	VERDICT_HELD: "This row's condition holds, but the pawn is finishing an action and reads no row at all until that ends.",
	VERDICT_WAITING: "This row's condition does not hold, so the pawn is not reading it.",
	VERDICT_TAUNTED: "The pawn is compelled and none of its rows are read at all.",
}

func _verdict_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color",
		Palette.TEAM_PLAYER if text == VERDICT_ACTING else (
			Palette.TEXT if text == VERDICT_READY else Palette.TEXT_DIM))
	label.set_script(GlossaryLabelScript)
	# Same reason every other chip on this screen sets it: `Label`'s engine
	# default is MOUSE_FILTER_IGNORE and a chip left at the default never gets a
	# hover, which is the defect this panel's own history records.
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.tooltip_text = String(VERDICT_HELP.get(text, ""))
	label.custom_minimum_size = Vector2(64.0, 0.0)
	return label

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
