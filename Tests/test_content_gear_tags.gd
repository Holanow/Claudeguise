extends "res://Tests/TestCase.gd"


## Issue 915: gear gates on Method crossed with Style and on nothing else.
## Role tags are synergy hooks now, because tag counts are unevenly distributed
## across classes and gating on them advantages whichever class carries most.


## Every class must be able to arm and dress itself, or a tag has been written
## too narrow and the equip screen simply shows an empty list. This is the same
## check #40 asked for on weapons, now that armour is gated too.
func test_every_class_can_equip_something_in_every_slot() -> void:
	for class_id in ClassLibrary.all_ids():
		var c := ClassLibrary.get_class_def(class_id)
		## Issue 918: HEAD is in the list now that the Great Helm and the Hood
		## ship; it was excluded only because no head item existed.
		for slot in [EquipmentDef.Slot.MAIN_HAND, EquipmentDef.Slot.OFF_HAND,
				EquipmentDef.Slot.HEAD, EquipmentDef.Slot.BODY,
				EquipmentDef.Slot.ACCESSORY]:
			var offered := _offered(c, slot)
			assert_false(offered.is_empty(),
				"%s has no %s it is allowed to equip" % [class_id, _slot_name(slot)])


## The gate has to refuse as well as permit, or it is a function that returns
## true. Every one of these is a real class against a real item.
func test_the_tags_refuse_the_classes_they_are_meant_to() -> void:
	_refuses(&"priest", &"rune_gauntlet", "a ranged caster must not take a melee Claw as its basic attack")
	_refuses(&"geysermancer", &"sword", "a magical class must not wield a Sword")
	_refuses(&"warrior", &"orb", "a martial class must not carry an Orb")
	_refuses(&"abomination", &"plate_mail", "Plate is MARTIAL and the Abomination is not")
	_refuses(&"warrior", &"robes", "Robes are MAGICAL and the Warrior is not")
	_refuses(&"warrior", &"quiver", "the Quiver is RANGED and the Warrior is MELEE")
	_refuses(&"siege_master", &"sword", "the Sword is MELEE and the Siege Master is not")


## And permit. Two tags is the specialised case and it has to still fit the one
## class that carries both.
func test_the_tags_permit_the_classes_they_are_meant_to() -> void:
	_permits(&"warrior", &"plate_mail", "Plate gates on MARTIAL alone since #915")
	_permits(&"abomination", &"rune_gauntlet", "the Abomination is MAGICAL and MELEE")
	_permits(&"geysermancer", &"robes", "Robes gate on MAGICAL alone since #915")
	_permits(&"siege_master", &"plate_mail", "a Martial Summoner wears plate, which is the #915 ruling")
	_permits(&"siege_master", &"bow", "the player's ruling: a Summoner also counts as RANGED")
	_permits(&"siege_master", &"quiver", "the same ruling, for the off hand #746 built")
	_permits(&"warrior", &"censer", "issue 489 untagged the Censer when it stopped granting INT")


## The acceptance criterion of #915, asserted against every shipped item: a
## gate may name a Method and a Style and nothing else.
func test_no_item_gates_on_a_tag_outside_method_and_style() -> void:
	var allowed := EquipmentDef.gate_tags()
	for id in ItemLibrary.all_ids():
		for t in ItemLibrary.get_equipment(id).required_tags:
			assert_true(allowed.has(t),
				"%s gates on tag %d, which is not a Method or a Style" % [id, t])

## And the gate still refuses, which is the one thing it exists for.
func test_a_wand_class_item_still_refuses_a_warrior() -> void:
	var staff := ItemLibrary.get_equipment(&"staff")
	assert_false(staff.allows_class(ClassLibrary.get_class_def(&"warrior")))


## A class's tags are derived from its own fields, never authored beside them.
## Change the class and the tag set follows, which is the property that stops
## the two from disagreeing.
func test_a_class_tag_set_is_derived_from_the_class() -> void:
	var warrior := ClassLibrary.get_class_def(&"warrior")
	var tags := warrior.tags()
	assert_true(tags.has(CG.Tag.MARTIAL) and tags.has(CG.Tag.MELEE), "method and style missing: %s" % [tags])
	assert_true(tags.has(CG.Tag.TANK) and tags.has(CG.Tag.DPS), "both roles missing: %s" % [tags])

	var both_roles_the_same := ClassLibrary.get_class_def(&"warrior").duplicate()
	both_roles_the_same.role_secondary = CG.Role.TANK
	assert_eq(both_roles_the_same.tags().size(), 3, "a class with one role twice should carry three tags")

	## Issue 915, the player's ruling: Summoner carries RANGED as well.
	var siege := ClassLibrary.get_class_def(&"siege_master").tags()
	assert_true(siege.has(CG.Tag.SUMMONER) and siege.has(CG.Tag.RANGED),
		"the Siege Master should count as both: %s" % [siege])


## `missing_tags` is what a screen needs to say *why*, so it must name the tag
## that is absent and not merely report a refusal.
func test_a_refusal_names_the_tag_the_class_lacks() -> void:
	var plate := ItemLibrary.get_equipment(&"plate_mail")
	assert_eq(plate.missing_tags(ClassLibrary.get_class_def(&"abomination")), [CG.Tag.MARTIAL] as Array[int])
	assert_eq(plate.missing_tags(ClassLibrary.get_class_def(&"warrior")), [] as Array[int])
	var sword := ItemLibrary.get_equipment(&"sword")
	assert_eq(sword.missing_tags(ClassLibrary.get_class_def(&"siege_master")), [CG.Tag.MELEE] as Array[int])


## Every pawn starts wearing what `PawnFactory` gives it, so a tag that refuses
## a starting piece is a pawn the equip screen would not let the player rebuild.
func test_every_starting_piece_passes_its_own_gate() -> void:
	for class_id in ClassLibrary.all_ids():
		var pawn := PawnFactory.make_starter_pawn(class_id, &"p", "p")
		for piece in [pawn.main_hand, pawn.off_hand, pawn.head, pawn.body, pawn.accessory]:
			if piece == null:
				continue
			assert_true(piece.allows_class(pawn.pawn_class),
				"%s starts with %s and could not equip it" % [class_id, piece.id])


## The table read directly rather than through a pawn, so a class missing from
## it fails here instead of silently starting with an empty off hand.
func test_the_off_hands_fill_empty_slots_would_give_are_legal_for_every_class() -> void:
	for class_id in ClassLibrary.all_ids():
		var c := ClassLibrary.get_class_def(class_id)
		var table := PawnFactory.STARTING_OFF_HAND
		assert_true(table.has(class_id), "%s has no starting off hand" % class_id)
		var piece := ItemLibrary.get_equipment(table.get(class_id, &""))
		assert_true(piece != null and piece.allows_class(c),
			"%s would start with %s and could not equip it" % [class_id, table.get(class_id)])

## Issue 822: `accessory` must stay empty, because `FloorRun._wearable_ids`
## filters every drop to a slot a living pawn can still fill and the censer is
## the only accessory in the game. A pawn with nothing empty receives no loot.
func test_filling_empty_slots_leaves_the_accessory_free_for_loot() -> void:
	var was := PawnFactory.FILL_EMPTY_SLOTS
	PawnFactory.FILL_EMPTY_SLOTS = true
	for class_id in ClassLibrary.all_ids():
		var pawn := PawnFactory.make_starter_pawn(class_id, class_id, "x")
		## Issue 917: the Priest's staff is two-handed and fills the slot itself.
		assert_true(pawn.off_hand != null or pawn.off_hand_blocked(),
			"%s got no off hand" % class_id)
		assert_eq(pawn.accessory, null, "%s filled its accessory; loot has nowhere to land" % class_id)
	PawnFactory.FILL_EMPTY_SLOTS = was


func _offered(c: ClassDef, slot: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ItemLibrary.all_ids():
		var item := ItemLibrary.get_equipment(id)
		if item.slot == slot and item.allows_class(c):
			out.append(id)
	return out

func _refuses(class_id: StringName, item_id: StringName, why: String) -> void:
	assert_false(ItemLibrary.get_equipment(item_id).allows_class(ClassLibrary.get_class_def(class_id)),
		"%s should refuse %s: %s" % [class_id, item_id, why])

func _permits(class_id: StringName, item_id: StringName, why: String) -> void:
	assert_true(ItemLibrary.get_equipment(item_id).allows_class(ClassLibrary.get_class_def(class_id)),
		"%s should permit %s: %s" % [class_id, item_id, why])

## One name per `EquipmentDef.Slot`. Three, against five slots, since #745 --
## so every BODY and ACCESSORY message indexed out of bounds and printed a
## SCRIPT ERROR on each gate run instead of the assertion's own text.
func _slot_name(slot: int) -> String:
	return ["main hand", "off hand", "head", "body", "accessory"][slot]
