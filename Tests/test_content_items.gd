extends "res://Tests/TestCase.gd"


## Issue 39: the base equipment types. Real Registry content, same pattern as
## test_content_classes.gd -- walks what is actually registered rather than a
## hand-typed list, so a future item is covered automatically.

func test_at_least_one_item_per_slot_is_registered() -> void:
	var ids := ItemLibrary.all_ids()
	assert_true(ids.size() > 0, "expected at least one item registered")
	var slots_seen := {}
	for id in ids:
		var item := ItemLibrary.get_equipment(id)
		assert_not_null(item, "registered id %s did not resolve" % id)
		slots_seen[item.slot] = true
	assert_true(slots_seen.has(EquipmentDef.Slot.MAIN_HAND), "no weapon registered")
	assert_true(slots_seen.has(EquipmentDef.Slot.BODY), "no armor registered")
	assert_true(slots_seen.has(EquipmentDef.Slot.ACCESSORY), "no accessory registered")


## Issue 28-style honesty check, same reasoning as ActionDef's own: an item a
## player cannot read is worse than no item.
func test_every_item_has_a_description() -> void:
	var checked := 0
	for id in ItemLibrary.all_ids():
		var item := ItemLibrary.get_equipment(id)
		checked += 1
		assert_false(item.description.is_empty(), "item %s has no description" % id)
	assert_true(checked > 0, "expected at least one item to check")


## README.md: weapons and accessories are percent, armor is flat plus an
## occasional CON percent. Every registered item should change something --
## an item with none of the capability fields set is a field nobody filled in.
func test_every_item_changes_something() -> void:
	for id in ItemLibrary.all_ids():
		var item := ItemLibrary.get_equipment(id)
		var changes_something := (
			not item.attribute_percent.is_empty()
			or not item.attribute_flat.is_empty()
			or item.damage_reduction > 0.0
			or item.resource_regen_percent_bonus > 0.0
			or not item.granted_actions.is_empty()
			or not item.modifiers.is_empty()
		)
		assert_true(changes_something, "item %s does not change anything" % id)


## Issue 489 restricted gear to Wisdom and actions; issue 746 added a
## capability layer beyond that (a shield's `damage_reduction`, a focus's
## `resource_regen_percent_bonus`, a quiver's `modifiers`), so only the percent
## layer and non-Wisdom flat bonuses are still forbidden.
func test_gear_grants_no_percent_and_no_flat_but_wisdom() -> void:
	var offenders := []
	for id in ItemLibrary.all_ids():
		var item := ItemLibrary.get_equipment(id)
		if not item.attribute_percent.is_empty():
			offenders.append("%s carries a percent bonus %s" % [id, item.attribute_percent])
		for a in item.attribute_flat.keys():
			if a != CG.Attribute.WIS:
				offenders.append("%s carries flat %s" % [id, CG.attribute_name(a)])
	assert_eq(offenders, [], "gear is a capability layer and these are numbers")


## And the other half of it: a piece that grants nothing at all is an object
## taking up a slot and a picker row. Issue 489 deleted eight of those; issue
## 746 widened what counts as "grants something" to match the wider capability
## layer above.
func test_no_registered_piece_is_inert() -> void:
	var inert := []
	for id in ItemLibrary.all_ids():
		var item := ItemLibrary.get_equipment(id)
		var grants_something := (
			not item.granted_actions.is_empty()
			or int(item.attribute_flat.get(CG.Attribute.WIS, 0)) != 0
			or item.damage_reduction > 0.0
			or item.resource_regen_percent_bonus > 0.0
			or not item.modifiers.is_empty()
		)
		if not grants_something:
			inert.append(String(id))
	assert_eq(inert, [], "these pieces do nothing at all")





func test_equipment_ids_are_unique_and_sorted() -> void:
	var ids := ItemLibrary.all_ids()
	var seen := {}
	for id in ids:
		assert_false(seen.has(id), "duplicate equipment id %s" % id)
		seen[id] = true
	# Was `ids.duplicate().sort()`, which is the same sort the function under
	# test calls -- the expectation was the output compared to itself and could
	# not fail. `Array[StringName].sort()` compares interned pointers, not text.
	var as_text: Array[String] = []
	for id in ids:
		as_text.append(String(id))
	var expected := as_text.duplicate()
	expected.sort()
	assert_eq(as_text, expected, "all_equipment_ids should be in alphabetical order")


## Issue 40: EquipmentDef.required_tags declares who may equip a piece, but
## nothing refuses a mismatched equip -- rook's own merge note asked for a
## content test that the declarations are coherent, in place of that
## enforcement. "Coherent" here means every registered class can actually
## equip at least one weapon: a Method with no legal weapon would be a class
## nobody can arm, which is the failure this field could silently cause if a
## restriction were set too narrow.
func test_every_class_can_equip_at_least_one_weapon() -> void:
	for class_id in ClassLibrary.all_ids():
		var c := ClassLibrary.get_class_def(class_id)
		var can_equip_something := false
		for item_id in ItemLibrary.all_ids():
			var item := ItemLibrary.get_equipment(item_id)
			if item.slot == EquipmentDef.Slot.MAIN_HAND and item.allows_class(c):
				can_equip_something = true
				break
		assert_true(can_equip_something, "%s (tags %s) has no weapon it is allowed to equip" % [class_id, c.tags()])
