extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Balance := preload("res://Scripts/Content/Balance.gd")
const Glossary := preload("res://Scripts/UI/Glossary.gd")
const GlossaryLabelScript := preload("res://Scripts/UI/GlossaryLabel.gd")
const ItemIconViewScript := preload("res://Scripts/UI/ItemIconView.gd")

## Issue 100: the pre-fight equip screen. Three slots per pawn, every effect in
## specific numbers, and the granted actions an item teaches.
##
## OWNER: wren.
##
## Built as a full-screen overlay added as a child of PartySelect, the same
## shape and the same reasoning as InspectPanel: opening it never loses the
## party selection underneath it. The two screens are deliberately the same
## layout -- pawn list on the left, detail on the right -- because they are two
## halves of one job. This one decides what a pawn *can* do; the plan editor
## decides what it *will* do.
##
## **Editing writes straight onto the PawnData.** `PartySelect._available` holds
## the same instances it puts into `RunConfig.party`, so assigning `pawn.armor`
## here is the whole edit. No apply step, nothing to serialize, exactly as the
## plan editor already works.
##
## The numbers on this screen are read from `Balance`, never restated. Every
## before/after pair is the same pawn measured twice: once as it is, and once
## through `_stripped`, a copy carrying the class and the manual attribute bonus
## and no equipment. A hand-written "+15% STR means +2" would go stale the first
## time a formula moved, and this screen exists to be trusted about numbers.

signal closed

const _TOUCH := Palette.TOUCH_TARGET_MIN

const HEADING := "Equip your pawns"

## Four sentences, the same budget as the plan editor's own how-to-play. The
## last one is the point of the feature and the reason the two screens are
## siblings: an item that grants a skill puts a new block in the plan editor.
const HOW_TO_PLAY := (
	"Each pawn wears one weapon, one armor and one accessory. " +
	"A weapon or accessory raises attributes by a percentage, armor adds flat points and absorbs a share of every hit. " +
	"An item a class cannot use is not offered. " +
	"Armor can also teach a skill, and a skill your gear grants becomes a block you can plan with in Edit your pawns' plans."
)

const EMPTY_CHOICE := "(nothing)"

## The seven attributes, in the order the plan editor's own chip row uses them.
const ATTRIBUTE_ORDER: Array = [
	CG.Attribute.STR, CG.Attribute.DEX, CG.Attribute.AGI, CG.Attribute.CON,
	CG.Attribute.INT, CG.Attribute.ATN, CG.Attribute.WIS,
]

var _pawns: Array[PawnData] = []
var _selected_index: int = 0

var _list_box: VBoxContainer = null
var _detail_box: VBoxContainer = null

## Same reasoning as InspectPanel._ready(): set_anchors_and_offsets_preset, not
## set_anchors_preset, because this node's rect is still (0,0) here and the
## latter tries to preserve it.
func _ready() -> void:
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
	# Both scroll containers need their own vertical EXPAND_FILL or they
	# collapse to their content's minimum size however much room the body has.
	# InspectPanel found this on a real launch, with the whole body rendering as
	# nothing at all; this screen is built the same way and would do the same.
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", int(Palette.SPACE_S))
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_list_box)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A ScrollContainer otherwise lets its child grow past its own width and
	# offers a sideways scrollbar nobody uses. The slot pickers are
	# SIZE_EXPAND_FILL and share the panel's width because of this line.
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

## free() rather than queue_free(), same as InspectPanel: a second selection can
## rebuild before a deferred deletion flushes, leaving stale nodes overlapping
## the new ones.
func _rebuild_list() -> void:
	for child in _list_box.get_children():
		child.free()
	for i in _pawns.size():
		var button := Button.new()
		button.text = _list_entry_text(_pawns[i])
		button.custom_minimum_size = Vector2(0.0, _TOUCH)
		button.toggle_mode = true
		button.button_pressed = i == _selected_index
		button.pressed.connect(_select.bind(i))
		_list_box.add_child(button)

## The list carries the count of filled slots, so a player scanning the party
## can see who is still naked without opening each pawn in turn.
func _list_entry_text(pawn: PawnData) -> String:
	return "%s  %d/3" % [pawn.display_name, pawn.equipment().size()]

func _select(index: int) -> void:
	if index < 0 or index >= _pawns.size():
		return
	_selected_index = index
	for i in _list_box.get_child_count():
		_list_box.get_child(i).button_pressed = i == index
	_build_detail(_pawns[index])

func _build_detail(pawn: PawnData) -> void:
	for child in _detail_box.get_children():
		child.free()
	_detail_box.add_child(_line(pawn.display_name, Palette.FONT_SIZE_HEADING, Palette.TEXT))
	if pawn.pawn_class == null:
		_detail_box.add_child(_line("No class assigned, so nothing can be equipped.",
			Palette.FONT_SIZE_BODY, Palette.TEXT_DIM))
		return

	var cls := pawn.pawn_class
	# The same three words the plan editor and the party cards print, built the
	# same way, so the two screens cannot describe one class differently.
	var tags := _line("%s · %s · %s" % [
			String(CG.Role.keys()[cls.role_primary]).capitalize(),
			String(CG.Style.keys()[cls.style]).capitalize(),
			String(CG.Method.keys()[cls.method]).capitalize(),
		], Palette.FONT_SIZE_BODY, Palette.TEXT_DIM)
	tags.set_script(GlossaryLabelScript)
	# Set here rather than left to GlossaryLabel._ready(): this panel is often
	# built outside a live tree, where _ready() never fires, and a Label's engine
	# default mouse_filter is IGNORE -- the exact reason every glossary chip on
	# this project was unhoverable until PR #76.
	tags.mouse_filter = Control.MOUSE_FILTER_STOP
	tags.tooltip_text = Glossary.class_tags_text(cls.role_primary, cls.style, cls.method)
	_detail_box.add_child(tags)

	_detail_box.add_child(_section_header("Slots"))
	for slot in [EquipmentDef.Slot.WEAPON, EquipmentDef.Slot.ARMOR, EquipmentDef.Slot.ACCESSORY]:
		for control in _slot_controls(pawn, slot):
			_detail_box.add_child(control)

	_detail_box.add_child(_section_header("What your gear is worth"))
	for control in _effect_controls(pawn):
		_detail_box.add_child(control)

	_detail_box.add_child(_section_header("Skills your gear grants"))
	for control in _granted_controls(pawn):
		_detail_box.add_child(control)

# ---------------------------------------------------------------------------
# Slots
# ---------------------------------------------------------------------------

func slot_name(slot: int) -> String:
	match slot:
		EquipmentDef.Slot.WEAPON:
			return "Weapon"
		EquipmentDef.Slot.ARMOR:
			return "Armor"
		_:
			return "Accessory"

func equipped(pawn: PawnData, slot: int) -> EquipmentDef:
	match slot:
		EquipmentDef.Slot.WEAPON:
			return pawn.weapon
		EquipmentDef.Slot.ARMOR:
			return pawn.armor
		_:
			return pawn.accessory

func _set_equipped(pawn: PawnData, slot: int, item: EquipmentDef) -> void:
	match slot:
		EquipmentDef.Slot.WEAPON:
			pawn.weapon = item
		EquipmentDef.Slot.ARMOR:
			pawn.armor = item
		_:
			pawn.accessory = item

## What this pawn may put in this slot. `EquipmentDef.allows` is the one place
## that answers the question, and the screen refuses by *not offering*, which is
## the behaviour `EquipmentDef.allowed_methods` asks for in its own doc comment:
## the player meets a restriction as an absence, never as an error message.
##
## Public so a test can assert the offer directly rather than reading captions
## back off an OptionButton.
func offered_items(pawn: PawnData, slot: int) -> Array[EquipmentDef]:
	var out: Array[EquipmentDef] = []
	if pawn.pawn_class == null:
		return out
	for id in Registry.all_equipment_ids():
		var item := Registry.get_equipment(id)
		if item == null or item.slot != slot:
			continue
		if not item.allows(pawn.pawn_class.method):
			continue
		out.append(item)
	return out

## One slot: a labelled picker, then the chosen item's effect spelled out in
## numbers underneath. Two controls rather than one row because the effect line
## wraps and a wrapping Label inside an HBoxContainer reports a near-zero
## minimum width, which is what made InspectPanel's attribute names render on
## top of each other.
func _slot_controls(pawn: PawnData, slot: int) -> Array[Control]:
	var out: Array[Control] = []
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Palette.SPACE_S))

	# Issue 127: the item's own icon, first thing on the row. `EquipmentIcons`
	# shipped in #117 with no caller anywhere and this is it -- the eleventh
	# built-and-unreachable feature on this project, and it was reachable only
	# because sable read my diff looking for their own API.
	#
	# `worn` is computed below for the effect line; the icon needs it first, so
	# it is read here and used twice rather than looked up twice.
	var worn := equipped(pawn, slot)
	var icon := Control.new()
	icon.set_script(ItemIconViewScript)
	# Called directly rather than left to the engine, the same reason every
	# panel on this screen does: this row is built while EquipPanel may not be
	# inside a live tree, and _ready() is where the icon takes its size.
	icon._ready()
	icon.slot = slot
	icon.item = worn
	row.add_child(icon)

	var label := Label.new()
	label.text = slot_name(slot)
	label.custom_minimum_size = Vector2(120.0, 0.0)
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	# TEXT_DIM, not TEXT: a slot name and a section header were the same size and
	# the same colour on the first capture, so the three sections read as one
	# flat list. Dimming the repeated word is what separates them, rather than
	# adding a rule or growing the header.
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(label)

	var items := offered_items(pawn, slot)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(0.0, _TOUCH)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Both lines, for the reason the plan editor's chips carry them:
	# fit_to_longest_item defaults to true and makes the control claim a minimum
	# width big enough for its longest *unselected* entry, which runs a row off
	# the right edge. clip_text governs drawing only and does not help alone.
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	picker.add_item(EMPTY_CHOICE)
	var current := 0
	for i in items.size():
		picker.add_item(items[i].display_name)
		if worn != null and items[i].id == worn.id:
			current = i + 1
	picker.selected = current
	if items.is_empty():
		picker.disabled = true
		picker.set_item_text(0, "(nothing this class can use)")
	else:
		picker.item_selected.connect(func(idx): _on_slot_selected(pawn, slot, items, idx))
	row.add_child(picker)
	out.append(row)

	out.append(_line(_slot_effect_text(worn), Palette.FONT_SIZE_SMALL,
		Palette.TEXT if worn != null else Palette.TEXT_DIM))
	return out

## Deferred, not immediate. The picker emitting `item_selected` is a child of
## `_detail_box`, and `_build_detail` frees every child of it -- freeing a node
## partway through emitting its own signal is a use-after-free the engine warns
## about loudly. The plan editor hit this on real button presses and fixed it
## the same way: defer the rebuild, not the free.
func _on_slot_selected(pawn: PawnData, slot: int, items: Array[EquipmentDef], index: int) -> void:
	_set_equipped(pawn, slot, null if index == 0 else items[index - 1])
	call_deferred("_refresh", pawn)

func _refresh(pawn: PawnData) -> void:
	_rebuild_list()
	_build_detail(pawn)

## An item's effect derived from its own fields rather than from its
## `description` string. Both exist for a reason: the description is the item in
## the player's language ("Heavy plate"), and this is the same item in numbers,
## which is what the issue asks a slot to show. Deriving it means an item added
## next week is described correctly here without anyone remembering to.
##
## Public so a test can assert the sentence without reaching into the tree.
func item_effect_text(item: EquipmentDef) -> String:
	if item == null:
		return "Empty."
	var parts: Array[String] = []
	for a in ATTRIBUTE_ORDER:
		var flat := int(item.attribute_flat.get(a, 0))
		if flat != 0:
			parts.append("%s %+d" % [CG.attribute_name(a), flat])
	for a in ATTRIBUTE_ORDER:
		var percent := float(item.attribute_percent.get(a, 0.0))
		if percent != 0.0:
			parts.append("%s %+d%%" % [CG.attribute_name(a), int(round(percent * 100.0))])
	if item.damage_reduction != 0.0:
		parts.append("absorbs %d%% of every hit" % int(round(item.damage_reduction * 100.0)))
	for action_id in item.granted_actions:
		parts.append("grants %s" % _action_display_name(action_id))
	if parts.is_empty():
		return "No effect."
	return ", ".join(parts) + "."

func _slot_effect_text(item: EquipmentDef) -> String:
	if item == null:
		return "Empty. Nothing in this slot."
	return item_effect_text(item)

# ---------------------------------------------------------------------------
# What the gear is worth
#
# Every number here is the same pawn measured twice through `Balance`: as it
# stands, and stripped of equipment. Nothing is restated from an item's own
# fields, because the interesting cases are the ones where they compound -- a
# flat +2 CON and a +10% CON on the same piece are not "+2 and +10%", they are
# a specific integer, and that integer is what a player is deciding on.
# ---------------------------------------------------------------------------

## The same pawn with the same class and the same manual bonus, wearing nothing.
## A fresh PawnData rather than clearing and restoring the real one: this runs
## on every rebuild, and a screen that briefly unequips the pawn it is drawing
## is one interrupted call away from saving that state.
func _stripped(pawn: PawnData) -> PawnData:
	var bare := PawnData.new()
	bare.id = pawn.id
	bare.display_name = pawn.display_name
	bare.pawn_class = pawn.pawn_class
	bare.attribute_bonus = pawn.attribute_bonus.duplicate()
	return bare

func _effect_controls(pawn: PawnData) -> Array[Control]:
	var out: Array[Control] = []
	var bare := _stripped(pawn)

	if pawn.equipment().is_empty():
		out.append(_line("Nothing equipped, so these are this pawn's own numbers.",
			Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))

	var attrs := HBoxContainer.new()
	attrs.add_theme_constant_override("separation", int(Palette.SPACE_M))
	for a in ATTRIBUTE_ORDER:
		var before := Balance.attribute(bare, a)
		var after := Balance.attribute(pawn, a)
		# Not `_line`: an autowrapping Label reports a near-zero minimum width,
		# so seven of them in one HBoxContainer draw on top of each other. The
		# plan editor found this on a real launch and these chips are the same
		# shape.
		var chip := Label.new()
		chip.set_script(GlossaryLabelScript)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.text = _stat_text(CG.attribute_name(a), before, after, 0)
		chip.tooltip_text = Glossary.attribute_text(a)
		chip.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
		chip.add_theme_color_override("font_color",
			Palette.HP_FULL if after != before else Palette.TEXT_DIM)
		attrs.add_child(chip)
	out.append(attrs)

	out.append(_derived_line("Health", Balance.max_hp(bare), Balance.max_hp(pawn)))
	out.append(_derived_line("Resource", Balance.max_resource(bare), Balance.max_resource(pawn)))
	# Units per second, not the per-tick number `Balance.move_speed` returns. A
	# tick is an implementation detail of the simulation and appears nowhere a
	# player looks.
	out.append(_derived_line_float("Move speed",
		Balance.move_speed(bare) * float(CG.TICKS_PER_SECOND),
		Balance.move_speed(pawn) * float(CG.TICKS_PER_SECOND), " units per second"))

	# Read off the armor rather than through `Balance.damage_reduction`, which
	# takes a CombatUnit that does not exist before a fight is built. Armor is
	# the only source of it on a pawn, which is the same branch that function
	# takes, and a content test holds that.
	var absorbed := 0.0 if pawn.armor == null else pawn.armor.damage_reduction
	out.append(_line("Damage absorbed: %d%% of every hit." % int(round(absorbed * 100.0)),
		Palette.FONT_SIZE_SMALL, Palette.HP_FULL if absorbed > 0.0 else Palette.TEXT_DIM))
	return out

func _derived_line(label: String, before: int, after: int) -> Label:
	return _line("%s: %s" % [label, _stat_text("", before, after, 0)],
		Palette.FONT_SIZE_SMALL, Palette.HP_FULL if after != before else Palette.TEXT_DIM)

func _derived_line_float(label: String, before: float, after: float, suffix: String) -> Label:
	var text := "%.1f" % before
	if not is_equal_approx(before, after):
		text = "%.1f to %.1f (%+.1f)" % [before, after, after - before]
	return _line("%s: %s%s." % [label, text, suffix], Palette.FONT_SIZE_SMALL,
		Palette.HP_FULL if not is_equal_approx(before, after) else Palette.TEXT_DIM)

## "STR 12" when nothing changed it, "STR 12 to 14 (+2)" when something did.
## Written out rather than shown as a bare delta: the issue asks for specific
## numbers, and a player choosing between two items wants the number they will
## be fighting with, not the size of the step.
func _stat_text(name: String, before: float, after: float, _digits: int) -> String:
	var prefix := "" if name == "" else name + " "
	if int(round(before)) == int(round(after)):
		return "%s%d" % [prefix, int(round(before))]
	return "%s%d to %d (%+d)" % [prefix, int(round(before)), int(round(after)),
		int(round(after)) - int(round(before))]

# ---------------------------------------------------------------------------
# Granted skills
#
# The point of the whole feature. `Registry.actions_for_pawn` is what the plan
# editor now asks as well, so what this section promises and what that screen
# offers cannot disagree -- they were two separate computations until issue 100,
# and the fight knew about a granted action while the plan editor did not.
# ---------------------------------------------------------------------------

func granted_action_ids(pawn: PawnData) -> Array[StringName]:
	var out: Array[StringName] = []
	for item in pawn.equipment():
		for action_id in item.granted_actions:
			if not out.has(action_id):
				out.append(action_id)
	return out

func _granted_controls(pawn: PawnData) -> Array[Control]:
	var out: Array[Control] = []
	var granted := granted_action_ids(pawn)
	if granted.is_empty():
		out.append(_line(
			"None. No item this pawn is wearing teaches a skill. Plate Mail is the one that does.",
			Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
		return out
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Palette.SPACE_M))
	for action_id in granted:
		row.add_child(_action_chip(action_id))
	out.append(row)
	out.append(_line(
		"Now a skill block in Edit your pawns' plans, on top of this pawn's own %d." % _class_action_count(pawn),
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
	return out

func _class_action_count(pawn: PawnData) -> int:
	return pawn.pawn_class.starting_actions.size() if pawn.pawn_class != null else 0

## Same construction as the plan editor's action chips, `mouse_filter` line
## included and for the same reason.
func _action_chip(action_id: StringName) -> Control:
	var chip := Label.new()
	chip.set_script(GlossaryLabelScript)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	var action: ActionDef = Registry.get_action(action_id)
	if action == null:
		chip.text = "%s (not registered)" % String(action_id).capitalize()
		chip.add_theme_color_override("font_color", Palette.HP_LOW)
		chip.tooltip_text = "This action is not in the registry, so nothing can use it."
		return chip
	chip.text = action.display_name
	chip.add_theme_color_override("font_color", Palette.HP_FULL)
	chip.tooltip_text = action.description if action.description != "" else "(no description yet)"
	return chip

func _action_display_name(action_id: StringName) -> String:
	var action: ActionDef = Registry.get_action(action_id)
	return action.display_name if action != null else String(action_id).capitalize()

func _section_header(text: String) -> Control:
	return _line(text, Palette.FONT_SIZE_BODY, Palette.TEXT)

func _line(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	return label
