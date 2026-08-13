extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PlanInterpreter := preload("res://Scripts/Plans/PlanInterpreter.gd")

## Issue 21b: look at your pawns between fights. Read-only — no editing, per
## the issue's own scope line. A full-screen overlay added as a child of
## whichever screen opens it (PartySelect or BattleView's end banner) rather
## than a Main-routed screen, so opening it never loses that screen's state
## (an in-progress party selection, a just-finished fight).
##
## OWNER: pike.
##
## Depends on teal's issue 21a for two things neither of which exists yet:
## `ActionDef.description` (the field is on the trunk, empty on every
## action — shows as empty here, which is correct and expected, not a bug)
## and `PlanInterpreter.describe_op(op, args)` (the function itself does not
## exist yet, proposed shape posted on the board for teal to confirm). Rather
## than call a function that is not there and go red for everyone the way
## issue 20's wiring did, a plan's own `display_name` (teal's real, already-
## authored text, e.g. "Guard when hurt") stands in for the block-by-block
## sentence until describe_op lands — one function swapped in once it does,
## nothing else about this file changes shape.

signal closed

const _TOUCH := Palette.TOUCH_TARGET_MIN

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
	title.text = "Inspect your pawns"
	title.add_theme_font_size_override("font_size", Palette.FONT_SIZE_HEADING)
	title.add_theme_color_override("font_color", Palette.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)

	var close_button := Button.new()
	close_button.text = "Back"
	close_button.custom_minimum_size = Vector2(0.0, _TOUCH)
	close_button.pressed.connect(close)
	top_row.add_child(close_button)

	# Everything on this screen is available to every pawn this slice — say so
	# once, rather than leaving "why does nothing look locked" as an open
	# question. Per issue 21's own instruction, since loot is out of scope.
	var availability := Label.new()
	availability.text = "Nothing is locked yet — every action and plan op is available to every pawn this slice."
	availability.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	availability.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(availability)

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
	_detail_box.add_child(_line(
		"%s · %s" % [_role_text(cls.role_primary), _style_method_text(cls.style, cls.method)],
		Palette.FONT_SIZE_BODY, Palette.TEXT_DIM))

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
		chip.text = "%s %d" % [CG.attribute_name(a), pawn.attribute(a)]
		chip.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
		chip.add_theme_color_override("font_color", Palette.TEXT)
		attrs.add_child(chip)
	_detail_box.add_child(attrs)

	_detail_box.add_child(_section_header("Actions"))
	if cls.starting_actions.is_empty():
		_detail_box.add_child(_line("No actions.", Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
	for action_id in cls.starting_actions:
		_detail_box.add_child(_action_line(action_id))

	_detail_box.add_child(_section_header("Plans, in priority order"))
	if pawn.plans.is_empty():
		_detail_box.add_child(_line(
			"No plans — this pawn runs on default behaviour alone (close, attack, retreat when hurt).",
			Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
	for i in pawn.plans.size():
		_detail_box.add_child(_plan_line(i + 1, pawn.plans[i]))

	var plan_action_ids := _actions_used_in_plans(pawn)
	var unused := cls.starting_actions.filter(func(a): return not plan_action_ids.has(a))
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

func _action_line(action_id: StringName) -> Control:
	var action := Registry.get_action(action_id)
	if action == null:
		return _line("%s (not registered)" % String(action_id).capitalize(), Palette.FONT_SIZE_SMALL, Palette.HP_LOW)
	var box := VBoxContainer.new()
	box.add_child(_line(action.display_name, Palette.FONT_SIZE_BODY, Palette.TEXT))
	var desc := action.description if action.description != "" else "(no description yet)"
	box.add_child(_line(desc, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
	return box

func _action_display_name(action_id: StringName) -> String:
	var action := Registry.get_action(action_id)
	return action.display_name if action != null else String(action_id).capitalize()

## Full block-by-block sentences depend on PlanInterpreter.describe_op
## (issue 21a, not landed — proposed shape posted on the board). The plan's
## own display_name is real, teal-authored text and stands in until then.
func _plan_line(priority: int, plan) -> Control:
	return _line("%d. %s" % [priority, plan.display_name],
		Palette.FONT_SIZE_BODY, Palette.TEXT)

func _section_header(text: String) -> Control:
	return _line(text, Palette.FONT_SIZE_BODY, Palette.TEXT)

func _line(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	return label

func _role_text(role: CG.Role) -> String:
	return String(CG.Role.keys()[role]).capitalize()

func _style_method_text(style: CG.Style, method: CG.Method) -> String:
	return "%s · %s" % [
		String(CG.Style.keys()[style]).capitalize(),
		String(CG.Method.keys()[method]).capitalize(),
	]
