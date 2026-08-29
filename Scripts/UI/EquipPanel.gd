extends Control
class_name EquipPanel

const GlossaryLabelScript := preload("res://Scripts/UI/GlossaryLabel.gd")
const ItemIconViewScript := preload("res://Scripts/UI/ItemIconView.gd")

## Issue 100: the pre-fight equip screen. Three slots per pawn, every effect in
## specific numbers, and the granted actions an item teaches.

signal closed

## Issue 351. WIS from an item sets the plan block budget, so the screen beside
## this one has to hear about a slot changing.
signal equipment_changed(pawn: PawnData)

const _TOUCH := Palette.TOUCH_TARGET_MIN

## Issue 744: the paper doll. Sized so a held weapon reads clearly; markers sit
## outside this radius, so the box has to be wider than the doll itself.
const DOLL_SIZE := 200.0
const DOLL_RADIUS := 62.0
const MARKER_SIZE := 34.0

## The heading and the four-sentence how-to-play now live in
## `Scenes/EquipPanel.tscn`. Four sentences is the same budget as the plan
## editor's own how-to-play, and the last one is the point of the feature and the
## reason the two screens are siblings: an item that grants a skill puts a new
## block in the plan editor. Keep it to four if you edit it in the editor.
const EMPTY_CHOICE := "(nothing)"

## The seven attributes, in the order the plan editor's own chip row uses them.
const ATTRIBUTE_ORDER: Array = [
	CG.Attribute.STR, CG.Attribute.DEX, CG.Attribute.AGI, CG.Attribute.CON,
	CG.Attribute.INT, CG.Attribute.ATN, CG.Attribute.WIS,
]

var _pawns: Array[PawnData] = []
var _selected_index: int = 0

## Issue 741: gear is read once when `CombatSim` builds a unit, the same as a
## plan, but changing it mid-fight has no staged form to land in -- there is
## no equipment equivalent of `FloorRun.carry_into` reading a per-pawn queue.
## Locking is the cheap, honest choice until that is asked for.
var _locked := false
var _lock_reason := ""

func set_locked(locked: bool, reason: String = "") -> void:
	_locked = locked
	_lock_reason = reason

## `new()` gives a bare Control with none of the tree. Everything static --
## backdrop, heading, how-to-play, the two scrolling columns -- is in
## `Scenes/EquipPanel.tscn`; the pawn list and the detail column are built per
## pawn below.
static func create() -> EquipPanel:
	return (load("res://Scenes/EquipPanel.tscn") as PackedScene).instantiate()

func _ready() -> void:
	theme = AppTheme.shared()
	%CloseButton.pressed.connect(close)

func open(pawns: Array[PawnData]) -> void:
	_pawns = pawns
	_selected_index = 0
	visible = true
	_rebuild_list()
	_select(0)

func close() -> void:
	visible = false
	closed.emit()

## Issue 351, and the same shape as InspectPanel.embed(): laid into a column of
## another screen, so the backdrop, the Back button and the pawn list all go.
var _embedded := false

func embed() -> void:
	_embedded = true
	visible = true
	%Backdrop.visible = false
	%CloseButton.visible = false
	%HowToPlay.visible = false
	%ListBox.get_parent().visible = false
	%Margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		%Margin.add_theme_constant_override("margin_" + side, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

func show_pawn(pawn: PawnData) -> void:
	_pawns = [pawn] as Array[PawnData]
	_selected_index = 0
	visible = true
	if _embedded:
		%Title.text = "Equipment"
	_build_detail(pawn)

## free() rather than queue_free(), same as InspectPanel: a second selection can
## rebuild before a deferred deletion flushes, leaving stale nodes overlapping
## the new ones.
func _rebuild_list() -> void:
	for child in %ListBox.get_children():
		child.free()
	for i in _pawns.size():
		var button := Button.new()
		button.text = _list_entry_text(_pawns[i])
		button.custom_minimum_size = Vector2(0.0, _TOUCH)
		button.toggle_mode = true
		button.button_pressed = i == _selected_index
		button.pressed.connect(_select.bind(i))
		%ListBox.add_child(button)

## The list carries the count of filled slots, so a player scanning the party
## can see who is still naked without opening each pawn in turn.
func _list_entry_text(pawn: PawnData) -> String:
	return "%s  %d/%d" % [pawn.display_name, pawn.equipment().size(), EquipmentDef.Slot.size()]

func _select(index: int) -> void:
	if index < 0 or index >= _pawns.size():
		return
	_selected_index = index
	for i in %ListBox.get_child_count():
		%ListBox.get_child(i).button_pressed = i == index
	_build_detail(_pawns[index])

func _build_detail(pawn: PawnData) -> void:
	for child in %DetailBox.get_children():
		child.free()
	## Embedded, the pawn's name and class are already on the panel above this
	## one in the same column, and printing them twice is what the first
	## capture of issue 351 showed.
	if not _embedded:
		%DetailBox.add_child(_line(pawn.display_name, Palette.FONT_SIZE_HEADING, Palette.TEXT))
	if pawn.pawn_class == null:
		%DetailBox.add_child(_line("No class assigned, so nothing can be equipped.",
			Palette.FONT_SIZE_BODY, Palette.TEXT_DIM))
		return

	if _locked:
		%DetailBox.add_child(_line(_lock_reason, Palette.FONT_SIZE_SMALL, Palette.HP_LOW))

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
	if not _embedded:
		%DetailBox.add_child(tags)

	## Issue 744: the doll centred above its own slots and stats. A
	## CenterContainer rather than a fixed offset, so the doll stays centred
	## whether the column is 1600px wide or a 240px popout tab.
	var center := CenterContainer.new()
	var doll := DollView.new()
	doll.pawn = pawn
	doll.custom_minimum_size = Vector2(DOLL_SIZE, DOLL_SIZE)
	center.add_child(doll)
	%DetailBox.add_child(center)

	%DetailBox.add_child(_section_header("Slots"))
	for slot in [EquipmentDef.Slot.MAIN_HAND, EquipmentDef.Slot.OFF_HAND, EquipmentDef.Slot.HEAD, EquipmentDef.Slot.BODY, EquipmentDef.Slot.ACCESSORY]:
		for control in _slot_controls(pawn, slot):
			%DetailBox.add_child(control)

	%DetailBox.add_child(_section_header("What your gear is worth"))
	for control in _effect_controls(pawn):
		%DetailBox.add_child(control)

	%DetailBox.add_child(_section_header("Actions"))
	for control in _action_controls(pawn):
		%DetailBox.add_child(control)

# ---------------------------------------------------------------------------
# Slots
# ---------------------------------------------------------------------------

static func slot_name(slot: int) -> String:
	match slot:
		EquipmentDef.Slot.MAIN_HAND:
			return "Main Hand"
		EquipmentDef.Slot.OFF_HAND:
			return "Off Hand"
		EquipmentDef.Slot.HEAD:
			return "Head"
		EquipmentDef.Slot.BODY:
			return "Body"
		_:
			return "Accessory"

func equipped(pawn: PawnData, slot: int) -> EquipmentDef:
	match slot:
		EquipmentDef.Slot.MAIN_HAND:
			return pawn.main_hand
		EquipmentDef.Slot.OFF_HAND:
			return pawn.off_hand
		EquipmentDef.Slot.HEAD:
			return pawn.head
		EquipmentDef.Slot.BODY:
			return pawn.body
		_:
			return pawn.accessory

func _set_equipped(pawn: PawnData, slot: int, item: EquipmentDef) -> void:
	match slot:
		EquipmentDef.Slot.MAIN_HAND:
			pawn.main_hand = item
		EquipmentDef.Slot.OFF_HAND:
			pawn.off_hand = item
		EquipmentDef.Slot.HEAD:
			pawn.head = item
		EquipmentDef.Slot.BODY:
			pawn.body = item
		_:
			pawn.accessory = item

## What this pawn may put in this slot. `EquipmentDef.allows_class` is the one
## place that answers the question.
func offered_items(pawn: PawnData, slot: int) -> Array[EquipmentDef]:
	return _slot_items(pawn, slot, true)

## Issue 474: the pieces this class is refused, so the picker can show them
## rather than silently be shorter. A player who cannot see the rule cannot
## learn it.
func refused_items(pawn: PawnData, slot: int) -> Array[EquipmentDef]:
	return _slot_items(pawn, slot, false)

func _slot_items(pawn: PawnData, slot: int, allowed: bool) -> Array[EquipmentDef]:
	var out: Array[EquipmentDef] = []
	if pawn.pawn_class == null:
		return out
	for id in ItemLibrary.all_ids():
		var item := ItemLibrary.get_equipment(id)
		if item == null or item.slot != slot:
			continue
		if item.allows_class(pawn.pawn_class) != allowed:
			continue
		out.append(item)
	return out

## The refusal in the player's words. `EquipmentDef.missing_tags` returns the
## tags and deliberately not a sentence, so the sentence is here.
func refusal_text(item: EquipmentDef, class_def: ClassDef) -> String:
	var missing := item.missing_tags(class_def)
	if missing.is_empty():
		return item.display_name
	var names: Array[String] = []
	for t in missing:
		names.append(String(CG.Tag.keys()[t]).capitalize())
	return "%s (needs %s)" % [item.display_name, " and ".join(names)]

## One slot: a labelled picker, then the chosen item's effect spelled out in
## numbers underneath. Two controls rather than one row because the effect line
## wraps and a wrapping Label inside an HBoxContainer reports a near-zero
## minimum width, which is what made InspectPanel's attribute names render on
## top of each other.
func _slot_controls(pawn: PawnData, slot: int) -> Array[Control]:
	var out: Array[Control] = []
	var row := HBoxContainer.new()

	# Issue 127: the item's own icon, first thing on the row. `EquipmentIcons`
	var worn := equipped(pawn, slot)
	var icon := Control.new()
	icon.set_script(ItemIconViewScript)
	# Called directly rather than left to the engine, the same reason every
	# panel on this screen does: this row is built while EquipPanel may not be
	# inside a live tree, and _ready() is where the icon takes its size.
	icon._ready()
	icon.slot = slot
	icon.item = worn
	## Issue 591: the icon carries what the item does, off the item's own
	## fields through `item_effect_text`, so a new piece of gear is described
	## correctly without anybody remembering to write a second sentence.
	icon.pin_title = worn.display_name if worn != null else "%s (empty)" % slot_name(slot)
	icon.tooltip_text = _slot_effect_text(worn)
	row.add_child(icon)

	var label := Label.new()
	label.text = slot_name(slot)
	label.custom_minimum_size = Vector2(120.0, 0.0)
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
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	AppTheme.keep_popup_on_screen(picker)
	picker.add_item(EMPTY_CHOICE)
	var current := 0
	for i in items.size():
		picker.add_item(items[i].display_name)
		if worn != null and items[i].id == worn.id:
			current = i + 1
	picker.selected = current
	# Issue 474: refused pieces go in as disabled rows *after* the offered ones,
	# so the index this signal carries still lands in `items`.
	var refused := refused_items(pawn, slot)
	for item in refused:
		picker.add_item(refusal_text(item, pawn.pawn_class))
		picker.set_item_disabled(picker.item_count - 1, true)
	if items.is_empty():
		picker.set_item_text(0, "(nothing this class can use)")
	# Disabled only when there is nothing to read either way. With refusals in
	# it the list is worth opening even when none of it can be taken.
	picker.disabled = _locked or (items.is_empty() and refused.is_empty())
	if not _locked and not items.is_empty():
		picker.item_selected.connect(func(idx): _on_slot_selected(pawn, slot, items, idx))
	row.add_child(picker)
	out.append(row)

	out.append(_line(_slot_effect_text(worn), Palette.FONT_SIZE_SMALL,
		Palette.TEXT if worn != null else Palette.TEXT_DIM))
	return out

## Deferred, not immediate. The picker emitting `item_selected` is a child of
## `%DetailBox`, and `_build_detail` frees every child of it -- freeing a node
## partway through emitting its own signal is a use-after-free the engine warns
## about loudly. The plan editor hit this on real button presses and fixed it
## the same way: defer the rebuild, not the free.
func _on_slot_selected(pawn: PawnData, slot: int, items: Array[EquipmentDef], index: int) -> void:
	_set_equipped(pawn, slot, null if index == 0 else items[index - 1])
	call_deferred("_refresh", pawn)
	equipment_changed.emit(pawn)

func _refresh(pawn: PawnData) -> void:
	_rebuild_list()
	_build_detail(pawn)

## An item's effect derived from its own fields rather than from its
## `description` string. Both exist for a reason: the description is the item in
## the player's language ("Heavy plate"), and this is the same item in numbers,
## which is what the issue asks a slot to show. Deriving it means an item added
## next week is described correctly here without anyone remembering to.
static func item_effect_text(item: EquipmentDef) -> String:
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

static func _slot_effect_text(item: EquipmentDef) -> String:
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

## The same pawn with the same class and the same manual bonus, wearing nothing.
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

	## Issue 744: `HFlowContainer`, not `HBoxContainer` -- seven chips in a row
	## that cannot wrap forced this panel's own minimum width past 320px, the
	## same failure mode #742 found in the plan editor's chip row.
	var attrs := HFlowContainer.new()
	attrs.add_theme_constant_override("h_separation", int(Palette.SPACE_M))
	attrs.add_theme_constant_override("v_separation", int(Palette.SPACE_XS))
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
		chip.tooltip_text = Glossary.attribute_text(a) + _roll_text(pawn, a)
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
	var absorbed := 0.0 if pawn.body == null else pawn.body.damage_reduction
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

## Issue 131: where this pawn's own number came from, when it is not simply the
## class's. The chip already spends its text on the gear delta, so the roll goes
## in the hover rather than competing with it. #343 is why this is here and not
## in `InspectPanel`: embedded, that panel's attribute row is cut and this one
## is the row a player reads.
func _roll_text(pawn: PawnData, a: CG.Attribute) -> String:
	if pawn.pawn_class == null:
		return ""
	var base := pawn.pawn_class.attribute(a)
	var delta := pawn.attribute(a) - base
	if delta == 0:
		return ""
	return "\n\nThis pawn rolled %+d on top of a %s baseline of %d." % [
		delta, pawn.pawn_class.display_name, base]

## "STR 12" when nothing changed it, "STR 12 to 14 (+2)" when something did.
func _stat_text(name: String, before: float, after: float, _digits: int) -> String:
	var prefix := "" if name == "" else name + " "
	if int(round(before)) == int(round(after)):
		return "%s%d" % [prefix, int(round(before))]
	return "%s%d to %d (%+d)" % [prefix, int(round(before)), int(round(after)),
		int(round(after)) - int(round(before))]

# ---------------------------------------------------------------------------
# Granted skills
#
# The point of the whole feature. `ActionLibrary.actions_for_pawn` is what the plan
# editor now asks as well, so what this section promises and what that screen
# offers cannot disagree -- they were two separate computations until issue 100,
# and the fight knew about a granted action while the plan editor did not.

func granted_action_ids(pawn: PawnData) -> Array[StringName]:
	var out: Array[StringName] = []
	for item in pawn.equipment():
		for action_id in item.granted_actions:
			if not out.has(action_id):
				out.append(action_id)
	return out

## Every action this pawn can call, gear included, and which of them the gear
## put there. The plans panel listed the same row without the gear in it, forty
## pixels away, and two lists that disagree teach a player to trust neither.
func _action_controls(pawn: PawnData) -> Array[Control]:
	var out: Array[Control] = []
	var available: Array = ActionLibrary.actions_for_pawn(pawn)
	if available.is_empty():
		out.append(_line("None. This pawn has nothing to call.",
			Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
		return out
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", int(Palette.SPACE_M))
	row.add_theme_constant_override("v_separation", int(Palette.SPACE_XS))
	for action_id in available:
		row.add_child(_action_chip(action_id))
	out.append(row)

	var granted := granted_action_ids(pawn)
	if granted.is_empty():
		out.append(_line(
			"All %d are this pawn's own; nothing it is wearing teaches a skill." % available.size(),
			Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM))
		return out
	var names := granted.map(func(a): return _action_display_name(a))
	out.append(_line(
		"%s came from gear, on top of this pawn's own %d." % [
			", ".join(names), _class_action_count(pawn)],
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
	var action: ActionDef = ActionLibrary.get_action(action_id)
	if action == null:
		chip.text = "%s (not registered)" % String(action_id).capitalize()
		chip.add_theme_color_override("font_color", Palette.HP_LOW)
		chip.tooltip_text = "This action is not in the registry, so nothing can use it."
		return chip
	chip.text = action.display_name
	chip.add_theme_color_override("font_color", Palette.HP_FULL)
	chip.tooltip_text = action.description if action.description != "" else "(no description yet)"
	return chip

static func _action_display_name(action_id: StringName) -> String:
	var action: ActionDef = ActionLibrary.get_action(action_id)
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

# ---------------------------------------------------------------------------
# Issue 744: the paper doll
#
# The pawn itself, not a picture of it. `UnitArt.sprites_for` is called
# directly rather than through `Silhouettes.draw_unit`, because the weapon in
# hand needs `pawn.main_hand.part` threaded through as `weapon_part` -- the
# same parameter `UnitView._sync_visual` already passes for the live arena.
# Slot markers are drawn, not separate nodes, so equipping an item redraws
# them for free the moment `queue_redraw` fires.
class DollView extends Control:
	var pawn: PawnData = null:
		set(value):
			pawn = value
			queue_redraw()

	func _draw() -> void:
		if pawn == null:
			return
		var center := size * 0.5
		_draw_body(center)
		_draw_markers(center)

	func _draw_body(center: Vector2) -> void:
		if pawn.pawn_class == null:
			draw_rect(Rect2(center - Vector2(DOLL_RADIUS, DOLL_RADIUS), Vector2(DOLL_RADIUS, DOLL_RADIUS) * 2.0), Color.BLACK)
			return
		var weapon_part: StringName = &"" if pawn.main_hand == null else pawn.main_hand.part
		var sprites := UnitArt.sprites_for(pawn.pawn_class.id, CG.Team.PLAYER, weapon_part)
		if sprites.is_empty():
			draw_rect(Rect2(center - Vector2(DOLL_RADIUS, DOLL_RADIUS), Vector2(DOLL_RADIUS, DOLL_RADIUS) * 2.0), Color.BLACK)
			return
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for s in sprites:
			var tex: Texture2D = s["tex"]
			# A missing part is a black square, the same ruling `Silhouettes.draw_unit` follows.
			if tex == null:
				draw_rect(Rect2(center - Vector2(DOLL_RADIUS, DOLL_RADIUS), Vector2(DOLL_RADIUS, DOLL_RADIUS) * 2.0), Color.BLACK)
				continue
			draw_texture_rect(tex, UnitArt.signed_rect(tex, DOLL_RADIUS, false, center), false, s["color"])

	## Five points on a ring outside the body, evenly spaced so none can
	## overlap another regardless of `MARKER_SIZE`: head at the top, then
	## clockwise main hand, accessory, body, off hand -- rook's slot order.
	func _draw_markers(center: Vector2) -> void:
		_slot_marker(_mark_rect(center, 0), EquipmentDef.Slot.HEAD, pawn.head)
		_slot_marker(_mark_rect(center, 1), EquipmentDef.Slot.MAIN_HAND, pawn.main_hand)
		_slot_marker(_mark_rect(center, 2), EquipmentDef.Slot.ACCESSORY, pawn.accessory)
		_slot_marker(_mark_rect(center, 3), EquipmentDef.Slot.BODY, pawn.body)
		_slot_marker(_mark_rect(center, 4), EquipmentDef.Slot.OFF_HAND, pawn.off_hand)

	func _mark_rect(center: Vector2, ring_index: int) -> Rect2:
		var angle := -PI * 0.5 + float(ring_index) * TAU / 5.0
		var p := center + Vector2(cos(angle), sin(angle)) * DOLL_RADIUS * 1.28
		return Rect2(p - Vector2(MARKER_SIZE, MARKER_SIZE) * 0.5, Vector2(MARKER_SIZE, MARKER_SIZE))

	func _slot_marker(rect: Rect2, slot: int, item: EquipmentDef) -> void:
		draw_rect(rect, Palette.HP_BACK)
		UIArt.draw_border(self, rect, EquipmentIcons.slot_color(slot), 1.0)
		if item == null:
			EquipmentIcons.draw_empty_slot(self, slot, rect)
		else:
			EquipmentIcons.draw_item(self, item, rect)
