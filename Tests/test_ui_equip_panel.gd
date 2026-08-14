extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")
const Balance := preload("res://Scripts/Content/Balance.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const EquipPanel := preload("res://Scripts/UI/EquipPanel.gd")
const InspectPanel := preload("res://Scripts/UI/InspectPanel.gd")
const PartySelect := preload("res://Scripts/UI/PartySelect.gd")
const ItemIconViewScript := preload("res://Scripts/UI/ItemIconView.gd")
const EquipmentIcons := preload("res://Scripts/Art/EquipmentIcons.gd")

## Issue 100: the pre-fight equip screen.
##
## Most fixtures are hand-built (the pattern the rest of Tests/test_ui_* uses)
## so the screen's behaviour does not depend on what content happens to be
## registered. The tests that are specifically about real items say so and use
## the Registry on purpose, because "Plate Mail grants a Block a Warrior can
## plan with" is a claim about the shipped game, not about a fixture.

func _make_class(method: CG.Method = CG.Method.MARTIAL) -> ClassDef:
	var cls := ClassDef.new()
	cls.id = &"test_class"
	cls.display_name = "Test Class"
	cls.role_primary = CG.Role.DPS
	cls.style = CG.Style.MELEE
	cls.method = method
	cls.starting_actions = [&"test_swing"]
	cls.base_attributes = {
		CG.Attribute.STR: 10, CG.Attribute.CON: 10, CG.Attribute.WIS: 8,
	}
	return cls

func _make_pawn(method: CG.Method = CG.Method.MARTIAL) -> PawnData:
	var pawn := PawnData.new()
	pawn.id = &"test_pawn"
	pawn.display_name = "Test Pawn"
	pawn.pawn_class = _make_class(method)
	return pawn

func _make_item(id: String, slot: int, methods: Array[CG.Method] = []) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = StringName(id)
	e.display_name = id.capitalize()
	e.slot = slot
	e.allowed_methods = methods
	return e

func _panel() -> EquipPanel:
	var panel := EquipPanel.new()
	panel._ready()
	return panel

# ---------------------------------------------------------------------------
# The point of the feature: a granted action reaches the plan editor.
# ---------------------------------------------------------------------------

## The one that matters. `plate_mail` is the only item in the game carrying
## `granted_actions`, and until issue 100 the fight honoured it while
## `InspectPanel._available_actions` returned `starting_actions` alone -- so the
## ability fired and could never be planned.
##
## Driven the way a player drives it: equip through the equip screen's own
## picker, then ask the plan editor what it offers. Not by setting `pawn.armor`
## directly, because the defect being guarded against is exactly a screen that
## agrees with itself and disagrees with its neighbour.
func test_equipping_plate_puts_its_block_in_the_plan_editor() -> void:
	var plate := Registry.get_equipment(&"plate_mail")
	assert_not_null(plate, "plate_mail must be registered for this test to mean anything")
	assert_false(plate.granted_actions.is_empty(), "plate_mail must grant an action")
	var granted: StringName = plate.granted_actions[0]

	var pawn := _make_pawn()
	var editor := InspectPanel.new()
	editor._ready()
	assert_false(editor._available_actions(pawn).has(granted),
		"before equipping, the plan editor must not offer the item's action")

	var panel := _panel()
	panel.open([pawn])
	var armors := panel.offered_items(pawn, EquipmentDef.Slot.ARMOR)
	var index := -1
	for i in armors.size():
		if armors[i].id == &"plate_mail":
			index = i
	assert_true(index >= 0, "the equip screen must offer plate_mail to a martial class")
	# +1 because entry 0 of the picker is "(nothing)".
	panel._on_slot_selected(pawn, EquipmentDef.Slot.ARMOR, armors, index + 1)

	assert_eq(pawn.armor, plate, "picking an item must write it onto the pawn")
	assert_true(editor._available_actions(pawn).has(granted),
		"after equipping, the plan editor must offer the item's action as a block")
	panel.free()
	editor.free()

## The negative half, and it is the one that would catch a fix that simply
## returned every action in the game. A pawn wearing nothing must be offered
## exactly what it was offered before issue 100 touched this.
func test_an_unequipped_pawn_is_offered_exactly_its_class_actions() -> void:
	var pawn := _make_pawn()
	var editor := InspectPanel.new()
	editor._ready()
	assert_eq(Array(editor._available_actions(pawn)), Array(pawn.pawn_class.starting_actions),
		"equipment must widen this list and nothing else")
	editor.free()

## The action also has to appear in the screen's own Actions row, not only in
## the pickers underneath it. A row saying "this pawn can do one thing" above a
## dropdown offering two is worse than either alone.
func test_the_actions_row_shows_a_granted_action() -> void:
	var pawn := _make_pawn()
	pawn.armor = Registry.get_equipment(&"plate_mail")
	var granted: StringName = pawn.armor.granted_actions[0]
	var editor := InspectPanel.new()
	editor._ready()
	editor.open([pawn])
	assert_true(_text_of(editor).contains(Registry.get_action(granted).display_name),
		"the granted action's name must appear somewhere on the plan editor")
	editor.free()

# ---------------------------------------------------------------------------
# Issue 127: the equipment icons had no caller.
#
# `EquipmentIcons` shipped in #117 with an icon for each of seventeen items and
# `EquipPanel` referenced it zero times, so the screen drew none of them -- the
# eleventh built-and-unreachable feature on this project. These tests exist to
# make that state fail rather than pass silently, so they assert placement on
# the *opened* screen and not only inside the row builder: a row builder nothing
# calls is exactly as unreachable as an icon nothing draws.
# ---------------------------------------------------------------------------

## The reachability guard. Opening the screen the way the screen is opened must
## put icons on it. This is the assertion the missing caller would have failed.
func test_opening_the_screen_puts_item_icons_on_it() -> void:
	var pawn := _make_pawn()
	var panel := _panel()
	panel.open([pawn])
	var icons := _icons(panel)
	assert_eq(icons.size(), 3, "one icon per slot must reach the opened screen, got %d" % icons.size())
	panel.free()

## Each icon must know which slot it stands for, because an empty slot draws its
## own plate rather than nothing -- an unfilled weapon slot still reads as a
## weapon slot. Asserted per slot, since one `slot` value applied to all three
## rows would satisfy a count-only check.
func test_each_slot_row_carries_an_icon_for_that_slot() -> void:
	var panel := _panel()
	var pawn := _make_pawn()
	for slot in [EquipmentDef.Slot.WEAPON, EquipmentDef.Slot.ARMOR, EquipmentDef.Slot.ACCESSORY]:
		var controls := panel._slot_controls(pawn, slot)
		var icons := _icons(controls[0])
		assert_eq(icons.size(), 1, "the %s row carries exactly one icon" % panel.slot_name(slot))
		assert_eq(icons[0].slot, slot, "the icon must draw the plate of its own slot")
		assert_true(icons[0].item == null, "an unequipped slot's icon holds no item")
		for c in controls:
			c.free()
	panel.free()

## And the filled case, against a real item rather than a fixture, because the
## claim is about the shipped game: wearing Plate Mail must put Plate Mail's own
## icon on the armor row.
func test_the_icon_follows_the_worn_item() -> void:
	var panel := _panel()
	var pawn := _make_pawn()
	pawn.armor = Registry.get_equipment(&"plate_mail")
	var controls := panel._slot_controls(pawn, EquipmentDef.Slot.ARMOR)
	var icons := _icons(controls[0])
	assert_eq(icons.size(), 1)
	assert_true(icons[0].item != null, "a worn item must reach its icon")
	assert_eq(icons[0].item.id, &"plate_mail")
	for c in controls:
		c.free()
	panel.free()

## The other half of "the art is reachable": an item the screen offers but
## `EquipmentIcons` has no glyph for falls back to a bare plate, and three items
## sharing a bare plate is indistinguishable from the icons working. Checked
## against what the screen really offers, both methods, all three slots.
func test_every_item_the_screen_offers_has_its_own_glyph() -> void:
	var panel := _panel()
	var missing: Array[String] = []
	for method in [CG.Method.MARTIAL, CG.Method.MAGICAL]:
		var pawn := _make_pawn(method)
		for slot in [EquipmentDef.Slot.WEAPON, EquipmentDef.Slot.ARMOR, EquipmentDef.Slot.ACCESSORY]:
			for item in panel.offered_items(pawn, slot):
				if not EquipmentIcons.has_glyph(item.id):
					missing.append(str(item.id))
	assert_eq(missing.size(), 0, "offered with no icon glyph: %s" % str(missing))
	panel.free()

## An icon must never sit between the player and the row it decorates. The
## picker underneath is the control a player reaches for.
func test_an_item_icon_does_not_eat_input_meant_for_the_row() -> void:
	var panel := _panel()
	var controls := panel._slot_controls(_make_pawn(), EquipmentDef.Slot.WEAPON)
	var icon := _icons(controls[0])[0]
	assert_eq(icon.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"Control defaults to STOP, which would make the icon swallow clicks")
	assert_true(icon.custom_minimum_size.x > 0.0, "an icon with no minimum size is drawn at nothing")
	for c in controls:
		c.free()
	panel.free()

func _text_of(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	if node is Button:
		out += node.text + "\n"
	if node is OptionButton:
		for i in node.item_count:
			out += node.get_item_text(i) + "\n"
	for child in node.get_children():
		out += _text_of(child)
	return out

# ---------------------------------------------------------------------------
# What the screen offers
# ---------------------------------------------------------------------------

## `EquipmentDef.allowed_methods` asks for refusal by absence rather than by
## error message: the screen must simply not offer the piece.
##
## Both halves, because "the list is filtered" and "the list is empty" pass the
## same one-sided assertion. A martial class is offered the Sword and refused
## the Orb; a magical class is refused the Sword and offered the Orb.
func test_a_class_is_not_offered_an_item_it_cannot_use() -> void:
	var panel := _panel()
	var martial_ids := _ids(panel.offered_items(_make_pawn(CG.Method.MARTIAL), EquipmentDef.Slot.WEAPON))
	var magical_ids := _ids(panel.offered_items(_make_pawn(CG.Method.MAGICAL), EquipmentDef.Slot.WEAPON))
	assert_true(martial_ids.has(&"sword"), "a martial class must be offered the Sword")
	assert_false(martial_ids.has(&"orb"), "a martial class must not be offered the Orb")
	assert_true(magical_ids.has(&"orb"), "a magical class must be offered the Orb")
	assert_false(magical_ids.has(&"sword"), "a magical class must not be offered the Sword")
	panel.free()

## Armor and accessories carry no `allowed_methods` today, deliberately (see
## `core_items.gd`), so both classes see the same list. Asserted rather than
## assumed: the filter reading the wrong field would show up here first.
func test_an_unrestricted_slot_is_offered_to_both_methods() -> void:
	var panel := _panel()
	for slot in [EquipmentDef.Slot.ARMOR, EquipmentDef.Slot.ACCESSORY]:
		assert_eq(_ids(panel.offered_items(_make_pawn(CG.Method.MARTIAL), slot)),
			_ids(panel.offered_items(_make_pawn(CG.Method.MAGICAL), slot)),
			"%s carries no method gate, so both classes must see one list" % panel.slot_name(slot))
	panel.free()

func _ids(items: Array[EquipmentDef]) -> Array[StringName]:
	var out: Array[StringName] = []
	for item in items:
		out.append(item.id)
	return out

## A slot only offers its own slot's items, which is the thing that would go
## wrong first if the filter were written against the id list alone.
func test_each_slot_offers_only_that_slot() -> void:
	var panel := _panel()
	var pawn := _make_pawn()
	for slot in [EquipmentDef.Slot.WEAPON, EquipmentDef.Slot.ARMOR, EquipmentDef.Slot.ACCESSORY]:
		var items := panel.offered_items(pawn, slot)
		assert_false(items.is_empty(), "%s must offer something" % panel.slot_name(slot))
		for item in items:
			assert_eq(item.slot, slot, "%s offered in the %s slot" % [item.id, panel.slot_name(slot)])
	panel.free()

## Choosing "(nothing)" has to be reachable, or a player who equips by accident
## cannot undo it.
func test_the_first_choice_clears_the_slot() -> void:
	var panel := _panel()
	var pawn := _make_pawn()
	var armors := panel.offered_items(pawn, EquipmentDef.Slot.ARMOR)
	panel._on_slot_selected(pawn, EquipmentDef.Slot.ARMOR, armors, 1)
	assert_not_null(pawn.armor, "picking entry 1 must equip the first offered item")
	panel._on_slot_selected(pawn, EquipmentDef.Slot.ARMOR, armors, 0)
	assert_eq(pawn.armor, null, "picking entry 0 must clear the slot")
	panel.free()

## The picker must not claim a wider minimum width than the panel has. Both
## lines are needed and neither is optional: `fit_to_longest_item` defaults to
## true and sizes the control to its longest *unselected* entry, which is what
## pushed the plan editor's rows off the right edge, and `clip_text` governs
## drawing rather than minimum size so it does not help alone.
func test_a_slot_picker_cannot_push_the_row_off_the_screen() -> void:
	var panel := _panel()
	var pawn := _make_pawn()
	var controls := panel._slot_controls(pawn, EquipmentDef.Slot.ARMOR)
	# Found by type, not by child index. It was `get_child(1)`, and issue 127
	# adding an icon to the front of the row turned that into a `Label`, which
	# aborted this method mid-way and recorded no assertion at all. A test that
	# stops measuring the moment somebody adds a control to the row is measuring
	# the row's shape, and the row's shape is not what this test is about.
	var picker: OptionButton = _first_of_type(controls[0], "OptionButton")
	assert_true(picker != null, "the slot row must carry a picker")
	assert_false(picker.fit_to_longest_item, "a picker sized to its longest entry runs off the row")
	assert_true(picker.clip_text)
	assert_eq(picker.get_item_text(0), panel.EMPTY_CHOICE, "clearing a slot must be the first choice")
	for c in controls:
		c.free()
	panel.free()

# ---------------------------------------------------------------------------
# Numbers
# ---------------------------------------------------------------------------

## The issue forbids qualitative words for scale, so every effect is a number.
## Derived from the item's fields, not from its prose description, which is why
## a fixture item with no description still reads correctly.
func test_an_items_effect_is_stated_in_numbers() -> void:
	var panel := _panel()
	var item := _make_item("test_plate", EquipmentDef.Slot.ARMOR)
	item.attribute_flat = {CG.Attribute.CON: 2}
	item.attribute_percent = {CG.Attribute.CON: 0.10}
	item.damage_reduction = 0.05
	var text := panel.item_effect_text(item)
	assert_true(text.contains("CON +2"), "flat bonus in numbers, got: %s" % text)
	assert_true(text.contains("CON +10%"), "percent bonus in numbers, got: %s" % text)
	assert_true(text.contains("5%"), "damage reduction in numbers, got: %s" % text)
	panel.free()

func test_an_empty_slot_reads_as_empty_rather_than_blank() -> void:
	var panel := _panel()
	assert_eq(panel.item_effect_text(null), "Empty.")
	panel.free()

## The compounding case, and the reason this screen measures rather than
## restates. Plate Mail is CON +2 *and* CON +10%: neither number on its own is
## what the pawn ends up with, and `Balance.attribute` is the only thing that
## knows the order they apply in.
func test_the_after_number_is_what_balance_says_not_the_items_own_field() -> void:
	var panel := _panel()
	var pawn := _make_pawn()
	pawn.armor = Registry.get_equipment(&"plate_mail")
	var bare := panel._stripped(pawn)
	assert_eq(bare.armor, null, "the stripped copy must wear nothing")
	assert_eq(bare.pawn_class, pawn.pawn_class, "and must keep the class it is measuring")
	assert_almost_eq(Balance.attribute(bare, CG.Attribute.CON), 10.0)
	assert_almost_eq(Balance.attribute(pawn, CG.Attribute.CON), 13.2, 0.0001,
		"(10 + 2) * 1.10, which is neither +2 nor +10%")
	panel.free()

## Stripping must not touch the pawn being drawn. A screen that unequips a pawn
## to measure it is one interrupted call away from saving that state.
func test_measuring_does_not_disturb_the_pawn() -> void:
	var panel := _panel()
	var pawn := _make_pawn()
	pawn.armor = Registry.get_equipment(&"plate_mail")
	panel.open([pawn])
	assert_eq(pawn.armor, Registry.get_equipment(&"plate_mail"),
		"drawing the screen must leave the pawn wearing what it wore")
	panel.free()

func test_an_unchanged_stat_reads_as_one_number_and_a_changed_one_reads_as_both() -> void:
	var panel := _panel()
	assert_eq(panel._stat_text("STR", 12.0, 12.0, 0), "STR 12")
	assert_eq(panel._stat_text("STR", 12.0, 14.0, 0), "STR 12 to 14 (+2)")
	panel.free()

# ---------------------------------------------------------------------------
# The screen itself
# ---------------------------------------------------------------------------

func test_the_panel_starts_hidden_and_opens_on_a_party() -> void:
	var panel := _panel()
	assert_false(panel.visible, "an overlay must not cover the screen it was built on")
	panel.open([_make_pawn()])
	assert_true(panel.visible)
	panel.close()
	assert_false(panel.visible)
	panel.free()

## Every hoverable Label on this screen sets `mouse_filter` explicitly, because
## `Label`'s engine default is IGNORE and `GlossaryLabel._ready()` does not fire
## for a panel built outside a live tree. That combination shipped one whole
## unreachable feature on this project (PR #76).
func test_every_glossary_chip_can_actually_receive_hover() -> void:
	var pawn := _make_pawn()
	pawn.armor = Registry.get_equipment(&"plate_mail")
	var panel := _panel()
	panel.open([pawn])
	var checked := 0
	for node in _all_nodes(panel):
		if node is Label and node.get_script() != null:
			assert_eq(node.mouse_filter, Control.MOUSE_FILTER_STOP,
				"a glossary chip left at Label's IGNORE default is unhoverable: '%s'" % node.text)
			checked += 1
	assert_true(checked > 0, "the screen must actually carry glossary chips")
	panel.free()

func _all_nodes(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_all_nodes(child))
	return out

## The first descendant of a built-in class, by name. `is_class` rather than an
## index, so adding a control to a row cannot silently repoint a test at the
## wrong node.
func _first_of_type(node: Node, type_name: String) -> Node:
	for n in _all_nodes(node):
		if n.is_class(type_name):
			return n
	return null

## Every descendant carrying `ItemIconView`'s script. Matched on the script
## rather than on the class, because there is no `class_name` in this project.
func _icons(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for n in _all_nodes(node):
		if n.get_script() == ItemIconViewScript:
			out.append(n)
	return out

## The three slots and the granted-skills section must all be on the screen, or
## the feature is unreachable however well it works underneath.
func test_the_screen_names_all_three_slots_and_the_granted_skill() -> void:
	var pawn := _make_pawn()
	pawn.armor = Registry.get_equipment(&"plate_mail")
	var panel := _panel()
	panel.open([pawn])
	var text := _text_of(panel)
	for word in ["Weapon", "Armor", "Accessory", "Plate Mail"]:
		assert_true(text.contains(word), "'%s' must be on the equip screen" % word)
	var granted: StringName = pawn.armor.granted_actions[0]
	assert_true(text.contains(Registry.get_action(granted).display_name),
		"the skill the armor grants must be named on the screen")
	assert_true(text.contains("Edit your pawns' plans"),
		"and the screen must say where that skill can be planned with")
	panel.free()

## A pawn wearing nothing must not read as broken, and must not claim a granted
## skill it does not have.
func test_a_naked_pawn_reads_as_empty_not_as_broken() -> void:
	var panel := _panel()
	panel.open([_make_pawn()])
	var text := _text_of(panel)
	assert_true(text.contains("0/3"), "the list must show how many slots are filled")
	assert_true(text.contains("None."), "granted skills must read as none, not as blank")
	panel.free()

# ---------------------------------------------------------------------------
# Reachability
# ---------------------------------------------------------------------------

## Ten features have shipped on this project built and unreachable. This asserts
## the button exists on the screen a player actually meets, and that pressing it
## opens the panel on the same pawn instances the fight is built from -- so an
## edit made here is an edit the fight sees, with no apply step to forget.
func test_party_select_can_reach_the_equip_screen_and_edits_reach_the_fight() -> void:
	var screen := PartySelect.new()
	screen._ready()
	var found: Button = null
	for node in _all_nodes(screen):
		if node is Button and node.text == "Equip pawns":
			found = node
	assert_not_null(found, "party select must carry a button that opens the equip screen")

	found.pressed.emit()
	assert_true(screen._equip_panel.visible, "pressing it must open the panel")

	var pawn: PawnData = screen.available_pawns()[0]
	var armors: Array = screen._equip_panel.offered_items(pawn, EquipmentDef.Slot.ARMOR)
	screen._equip_panel._on_slot_selected(pawn, EquipmentDef.Slot.ARMOR, armors, 1)
	screen.toggle_pawn(pawn, true)
	assert_eq(screen.current_config().party[0].armor, armors[0],
		"the pawn handed to the fight must be the pawn that was equipped")
	screen.free()
