extends "res://Tests/TestCase.gd"


## Issue 39: the base equipment types. Real Registry content, same pattern as
## test_content_classes.gd -- walks what is actually registered rather than a
## hand-typed list, so a future item is covered automatically.

func test_at_least_one_item_per_slot_is_registered() -> void:
	var ids := Registry.all_equipment_ids()
	assert_true(ids.size() > 0, "expected at least one item registered")
	var slots_seen := {}
	for id in ids:
		var item := Registry.get_equipment(id)
		assert_not_null(item, "registered id %s did not resolve" % id)
		slots_seen[item.slot] = true
	assert_true(slots_seen.has(EquipmentDef.Slot.WEAPON), "no weapon registered")
	assert_true(slots_seen.has(EquipmentDef.Slot.ARMOR), "no armor registered")
	assert_true(slots_seen.has(EquipmentDef.Slot.ACCESSORY), "no accessory registered")


## Issue 28-style honesty check, same reasoning as ActionDef's own: an item a
## player cannot read is worse than no item.
func test_every_item_has_a_description() -> void:
	var checked := 0
	for id in Registry.all_equipment_ids():
		var item := Registry.get_equipment(id)
		checked += 1
		assert_false(item.description.is_empty(), "item %s has no description" % id)
	assert_true(checked > 0, "expected at least one item to check")


## README.md: weapons and accessories are percent, armor is flat plus an
## occasional CON percent. Every registered item should change something --
## an item with no attribute_percent, no attribute_flat, no damage_reduction
## and no granted_actions is a field nobody filled in.
func test_every_item_changes_something() -> void:
	for id in Registry.all_equipment_ids():
		var item := Registry.get_equipment(id)
		var changes_something := (
			not item.attribute_percent.is_empty()
			or not item.attribute_flat.is_empty()
			or item.damage_reduction > 0.0
			or not item.granted_actions.is_empty()
		)
		assert_true(changes_something, "item %s does not change anything" % id)


func test_weapons_and_accessories_are_percent_not_flat() -> void:
	for id in Registry.all_equipment_ids():
		var item := Registry.get_equipment(id)
		if item.slot == EquipmentDef.Slot.WEAPON or item.slot == EquipmentDef.Slot.ACCESSORY:
			assert_true(item.attribute_flat.is_empty(), "%s is a weapon/accessory but has a flat bonus, per README these should be percent" % id)
			assert_false(item.attribute_percent.is_empty(), "%s is a weapon/accessory but has no percent bonus" % id)


func test_armor_is_flat_with_optional_con_percent() -> void:
	for id in Registry.all_equipment_ids():
		var item := Registry.get_equipment(id)
		if item.slot == EquipmentDef.Slot.ARMOR:
			assert_false(item.attribute_flat.is_empty(), "%s is armor but has no flat bonus" % id)
			for a in item.attribute_percent.keys():
				assert_eq(a, CG.Attribute.CON, "%s is armor with a percent bonus on something other than CON" % id)


func test_equipment_ids_are_unique_and_sorted() -> void:
	var ids := Registry.all_equipment_ids()
	var seen := {}
	for id in ids:
		assert_false(seen.has(id), "duplicate equipment id %s" % id)
		seen[id] = true
	# Was `ids.duplicate().sort()`, which is the same sort the function under
	# test calls -- the expectation was the output compared to itself and could
	# not fail. `Array[StringName].sort()` compares interned pointers, not text.
	# See `Registry._sort_ids`.
	var as_text: Array[String] = []
	for id in ids:
		as_text.append(String(id))
	var expected := as_text.duplicate()
	expected.sort()
	assert_eq(as_text, expected, "all_equipment_ids should be in alphabetical order")


## Issue 40: EquipmentDef.allowed_methods declares who may equip a piece, but
## nothing refuses a mismatched equip -- rook's own merge note asked for a
## content test that the declarations are coherent, in place of that
## enforcement. "Coherent" here means every registered class can actually
## equip at least one weapon: a Method with no legal weapon would be a class
## nobody can arm, which is the failure this field could silently cause if a
## restriction were set too narrow.
func test_every_class_can_equip_at_least_one_weapon() -> void:
	for class_id in Registry.all_class_ids():
		var c := Registry.get_class_def(class_id)
		var can_equip_something := false
		for item_id in Registry.all_equipment_ids():
			var item := Registry.get_equipment(item_id)
			if item.slot == EquipmentDef.Slot.WEAPON and item.allows(c.method):
				can_equip_something = true
				break
		assert_true(can_equip_something, "%s (method %s) has no weapon it is allowed to equip" % [class_id, CG.Method.keys()[c.method]])
