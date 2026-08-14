extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PlanInterpreter := preload("res://Scripts/Plans/PlanInterpreter.gd")
const PlanBlockScript := preload("res://Scripts/Core/PlanBlock.gd")

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
## Each CONDITION op reads a differently-shaped argument: `always` reads
## nothing, `self_hp_below_fraction`/`ally_below_hp_fraction` read a 0-1
## `fraction`, `self_resource_at_least` reads an int `amount`,
## `enemy_in_range` reads a float `range`. `_CONDITION_ARG_SHAPE` below is that
## mapping as one small table read once, rather than a branch repeated at
## every call site that needs it (the picker, the default-args-on-swap, the
## value editor all read the same table). It duplicates a fact
## `PlanInterpreter._eval_condition`'s own match statement already encodes —
## accepted rather than pushed into PlanInterpreter itself because the two
## other places that inform an editor's choices (`TARGETING_OPS`,
## `starting_actions`) were already public with no shape attached (none of
## the targeting ops read args at all), so this is the one new fact about
## PlanInterpreter's contract this screen depends on. If `CONDITION_OPS` ever
## grows, this table needs a matching entry — same maintenance shape as the
## `_fail`-on-unknown-op check in PlanInterpreter itself, and small for the
## same reason: five ops, one whitelist, both manager-owned and stable.
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

## op -> {arg_key, kind, min, max, step}. "none" carries no value editor.
## "fraction" edits as a 0-100 percent and stores back as 0.0-1.0, matching
## how describe_op already formats it ("self hp below 35%").
const _CONDITION_ARG_SHAPE := {
	&"always": {"kind": "none"},
	&"self_hp_below_fraction": {"kind": "fraction", "key": "fraction", "default": 0.5},
	&"ally_below_hp_fraction": {"kind": "fraction", "key": "fraction", "default": 0.5},
	&"self_resource_at_least": {"kind": "amount", "key": "amount", "min": 0, "max": 999, "step": 1, "default": 0},
	&"enemy_in_range": {"kind": "range", "key": "range", "min": 0, "max": 1000, "step": 10, "default": 100.0},
}

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
	_detail_box.add_child(_line(
		"Earliest plan whose condition holds is the one that fires. Reorder with the arrows; " +
		"swap the condition, targeting or action from what this pawn actually has.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
	if pawn.plans.is_empty():
		_detail_box.add_child(_line(
			"No plans — this pawn runs on default behaviour alone (close, attack, retreat when hurt).",
			Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
	for i in pawn.plans.size():
		_detail_box.add_child(_plan_row(i + 1, pawn.plans[i], pawn, i))

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

## "1. Guard when hurt — when self hp below 35%: target self, then use
## Warrior Guard." The plan's own display_name names it; describe_op reads
## the condition and each block back in a player's language.
func _plan_sentence(priority: int, plan) -> String:
	var condition_text := "always" if plan.condition == null \
		else PlanInterpreter.describe_op(plan.condition.op, plan.condition.args)
	var block_texts: Array[String] = []
	for block in plan.blocks:
		block_texts.append(PlanInterpreter.describe_op(block.op, block.args))
	var body := ", then ".join(block_texts) if not block_texts.is_empty() else "(no blocks)"
	return "%d. %s — when %s: %s." % [priority, plan.display_name, condition_text, body]

## One plan, as its sentence plus its editing controls: reorder arrows above
## the sentence, and a picker below for every TARGETING or ACTION block it
## carries. Rebuilds the whole detail panel on any change rather than trying
## to patch one label in place — plans are short and this screen is not on a
## hot path, so simplicity wins over an incremental update.
func _plan_row(priority: int, plan, pawn: PawnData, index: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Palette.SPACE_XS))

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(Palette.SPACE_S))

	var up := Button.new()
	up.text = "^"
	up.custom_minimum_size = Vector2(_TOUCH, _TOUCH)
	up.disabled = index == 0
	up.pressed.connect(_move_plan.bind(pawn, index, -1))
	header.add_child(up)

	var down := Button.new()
	down.text = "v"
	down.custom_minimum_size = Vector2(_TOUCH, _TOUCH)
	down.disabled = index == pawn.plans.size() - 1
	down.pressed.connect(_move_plan.bind(pawn, index, 1))
	header.add_child(down)

	var sentence := _line(_plan_sentence(priority, plan), Palette.FONT_SIZE_BODY, Palette.TEXT)
	sentence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sentence)
	box.add_child(header)

	box.add_child(_condition_editor(plan))

	for block in plan.blocks:
		if block.kind == PlanBlockScript.Kind.TARGETING and PlanInterpreter.TARGETING_OPS.has(block.op):
			box.add_child(_targeting_picker(block))
		elif block.kind == PlanBlockScript.Kind.ACTION and block.op == &"use_action":
			box.add_child(_action_picker(pawn, block))

	return box

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
func _targeting_picker(block) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Palette.SPACE_S))
	row.add_child(_tag_label("Targeting:"))
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(0.0, _TOUCH)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current := 0
	for i in PlanInterpreter.TARGETING_OPS.size():
		var op: StringName = PlanInterpreter.TARGETING_OPS[i]
		picker.add_item(_cap_first(PlanInterpreter.describe_op(op, {})))
		if op == block.op:
			current = i
	picker.selected = current
	picker.item_selected.connect(func(idx): _set_targeting(block, PlanInterpreter.TARGETING_OPS[idx]))
	row.add_child(picker)
	return row

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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Palette.SPACE_S))
	row.add_child(_tag_label("Action:"))
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(0.0, _TOUCH)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var choices: Array = pawn.pawn_class.starting_actions if pawn.pawn_class != null else []
	if choices.is_empty():
		picker.add_item("(no actions)")
		picker.disabled = true
		row.add_child(picker)
		return row
	var current_id: StringName = block.args.get("action_id", &"")
	var current := 0
	for i in choices.size():
		var action_id: StringName = choices[i]
		picker.add_item(_action_display_name(action_id))
		if action_id == current_id:
			current = i
	picker.selected = current
	picker.item_selected.connect(func(idx): _set_action(block, choices[idx]))
	row.add_child(picker)
	return row

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
	row.add_theme_constant_override("separation", int(Palette.SPACE_S))
	row.add_child(_tag_label("Condition:"))

	var current_op: StringName = plan.condition.op if plan.condition != null else &"always"
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(0.0, _TOUCH)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current := 0
	for i in PlanInterpreter.CONDITION_OPS.size():
		var op: StringName = PlanInterpreter.CONDITION_OPS[i]
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
	picker.item_selected.connect(func(idx): _set_condition_op(plan, PlanInterpreter.CONDITION_OPS[idx]))
	row.add_child(picker)

	var shape: Dictionary = _CONDITION_ARG_SHAPE.get(current_op, {"kind": "none"})
	if shape.get("kind") != "none" and plan.condition != null:
		row.add_child(_condition_value_editor(plan.condition, shape))
	return row

func _default_condition_args(op: StringName) -> Dictionary:
	var shape: Dictionary = _CONDITION_ARG_SHAPE.get(op, {"kind": "none"})
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

## One SpinBox, shaped by `_CONDITION_ARG_SHAPE`. "fraction" is the one case
## that does not store what it shows: the control reads and writes whole
## percent (0-100) because that is what `describe_op` prints, and it is
## rescaled to the 0.0-1.0 `PlanInterpreter` actually reads on the way out.
func _condition_value_editor(block, shape: Dictionary) -> Control:
	var spin := SpinBox.new()
	spin.custom_minimum_size = Vector2(0.0, _TOUCH)
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

## Issue 53 sweep: a short fixed prefix ("Targeting:", "Action:",
## "Condition:") sitting beside a SIZE_EXPAND_FILL picker in an
## HBoxContainer. _line's autowrap makes a Label report a near-zero minimum
## width -- the same bug already found and worked around for the Attributes
## chips above -- so the container gave it ~0 width and the picker's own
## text was drawn starting at the same x position: "Targeting:" and the
## picker's "Self" overlapped into "TaSelfting:" on a real launch
## (Screenshots/sweep_inspect_plan_editor_*). No autowrap on a string this
## short; it never needs to wrap.
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
