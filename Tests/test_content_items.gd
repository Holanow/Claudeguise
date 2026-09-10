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
## `resource_regen_percent_bonus`, a quiver's `modifiers`); issue 790 removed
## Wisdom, so the percent layer and every flat attribute bonus are forbidden.
func test_gear_grants_no_percent_and_no_flat_attribute() -> void:
	var offenders := []
	for id in ItemLibrary.all_ids():
		var item := ItemLibrary.get_equipment(id)
		if not item.attribute_percent.is_empty():
			offenders.append("%s carries a percent bonus %s" % [id, item.attribute_percent])
		for a in item.attribute_flat.keys():
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


## Issue 793: the three cloth body pieces and the censer went inert when #790
## removed the attribute they existed to grant. Each one is proved through the
## call the simulation itself makes, not by reading the field back.
const CLOTH_ARMOR := {
	&"priest": &"robes",
	&"siege_master": &"silk_wraps",
	&"abomination": &"gown",
}

func test_cloth_armor_reduces_damage_for_the_pawn_that_starts_in_it() -> void:
	for class_id in CLOTH_ARMOR:
		var pawn := PawnFactory.make_starter_pawn(class_id, &"probe", "Probe")
		assert_eq(pawn.body.id, CLOTH_ARMOR[class_id],
			"%s no longer starts in %s" % [class_id, CLOTH_ARMOR[class_id]])
		assert_almost_eq(Balance.gear_damage_reduction(pawn), 0.05, 0.0001,
			"%s wears %s and gets no mitigation from it" % [class_id, CLOTH_ARMOR[class_id]])


## The negative half: strip the body slot and the mitigation goes with it, so
## the number above comes from the armor rather than from anything else worn.
func test_taking_the_cloth_off_removes_the_mitigation() -> void:
	for class_id in CLOTH_ARMOR:
		var pawn := PawnFactory.make_starter_pawn(class_id, &"probe", "Probe")
		pawn.body = null
		assert_almost_eq(Balance.gear_damage_reduction(pawn), 0.0, 0.0001,
			"%s keeps mitigation with nothing in the body slot" % class_id)


func _wearing_censer() -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.hp = 40
	u.hp_max = 40
	u.pawn = PawnData.new()
	u.pawn.accessory = ItemLibrary.get_equipment(&"censer")
	return u

func _plain_action() -> ActionDef:
	var h := HitEffect.new()
	h.damage_type = CG.DamageType.PHYSICAL
	h.power_scale = 1.0
	var a := ActionDef.new()
	a.id = &"probe_swing"
	a.effects = [h] as Array[AbilityEffect]
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 40.0
	return a

## No starter pawn wears an accessory, so the fingerprint never exercises this
## and the assertion below is the only thing that proves the censer works.
func test_the_censer_slows_what_its_wearer_hits() -> void:
	var out := AbilityModifiers.added_statuses(_wearing_censer(), _plain_action())
	assert_eq(out.size(), 1, "the censer adds nothing to a landed hit")
	assert_eq(int(out[0]["status"]), int(CG.Status.SLOWED), "the censer should add Slowed")
	assert_eq(int(out[0]["ticks"]), 45)
	assert_almost_eq(float(out[0]["chance"]), 0.25, 0.0001)


## And it stays quiet on a pawn that is not wearing one.
func test_a_pawn_without_a_censer_adds_nothing() -> void:
	var u := _wearing_censer()
	u.pawn.accessory = null
	assert_eq(AbilityModifiers.added_statuses(u, _plain_action()), [],
		"an empty accessory slot must add no status")
