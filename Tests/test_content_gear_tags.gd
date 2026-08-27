extends "res://Tests/TestCase.gd"


## Issue 131: gear is gated on a set of tags drawn from more than one axis, and
## more specialised gear names more of them. The player's own example is a kite
## shield at MARTIAL against a tower shield at MARTIAL and TANK.


## Every class must be able to arm and dress itself, or a tag has been written
## too narrow and the equip screen simply shows an empty list. This is the same
## check #40 asked for on weapons, now that armour is gated too.
func test_every_class_can_equip_something_in_every_slot() -> void:
	for class_id in Registry.all_class_ids():
		var c := ClassLibrary.get_class_def(class_id)
		for slot in [EquipmentDef.Slot.WEAPON, EquipmentDef.Slot.ARMOR, EquipmentDef.Slot.ACCESSORY]:
			var offered := _offered(c, slot)
			assert_false(offered.is_empty(),
				"%s has no %s it is allowed to equip" % [class_id, _slot_name(slot)])


## The gate has to refuse as well as permit, or it is a function that returns
## true. Every one of these is a real class against a real item.
func test_the_tags_refuse_the_classes_they_are_meant_to() -> void:
	_refuses(&"priest", &"sickle", "a ranged caster must not take a melee Claw as its basic attack")
	_refuses(&"geysermancer", &"sword", "a magical class must not wield a Sword")
	_refuses(&"warrior", &"orb", "a martial class must not wield an Orb")
	_refuses(&"abomination", &"plate_mail", "Plate is MARTIAL and the Abomination is not")
	_refuses(&"siege_master", &"plate_mail", "Plate is TANK and the Siege Master is not")
	_refuses(&"geysermancer", &"gown", "the Gown is the anti-support's and the Geysermancer is not one")


## And permit. Two tags is the specialised case and it has to still fit the one
## class that carries both.
func test_the_tags_permit_the_classes_they_are_meant_to() -> void:
	_permits(&"warrior", &"plate_mail", "the Warrior is MARTIAL and TANK")
	_permits(&"abomination", &"sickle", "the Abomination is MAGICAL and MELEE")
	_permits(&"geysermancer", &"robes", "the Geysermancer's secondary role is SUPPORT")
	_permits(&"siege_master", &"gown", "the Siege Master's secondary role is ANTI_SUPPORT")
	_permits(&"warrior", &"censer", "issue 489 untagged the Censer when it stopped granting INT")


## The whole point of one flat namespace: a requirement can name a Method and a
## Role at once. If every item's tags came from a single axis the enum would be
## three enums again.
func test_at_least_one_item_requires_tags_from_two_different_axes() -> void:
	var plate := ItemLibrary.get_equipment(&"plate_mail")
	assert_eq(plate.required_tags, [CG.Tag.MARTIAL, CG.Tag.TANK] as Array[int])
	var sickle := ItemLibrary.get_equipment(&"sickle")
	assert_eq(sickle.required_tags, [CG.Tag.MAGICAL, CG.Tag.MELEE] as Array[int])


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


## `missing_tags` is what a screen needs to say *why*, so it must name the tag
## that is absent and not merely report a refusal.
func test_a_refusal_names_the_tag_the_class_lacks() -> void:
	var plate := ItemLibrary.get_equipment(&"plate_mail")
	assert_eq(plate.missing_tags(ClassLibrary.get_class_def(&"abomination")), [CG.Tag.MARTIAL] as Array[int])
	assert_eq(plate.missing_tags(ClassLibrary.get_class_def(&"siege_master")), [CG.Tag.TANK] as Array[int])
	assert_eq(plate.missing_tags(ClassLibrary.get_class_def(&"warrior")), [] as Array[int])


## Every pawn starts wearing what `PawnFactory` gives it, so a tag that refuses
## a starting piece is a pawn the equip screen would not let the player rebuild.
func test_every_starting_piece_passes_its_own_gate() -> void:
	for class_id in Registry.all_class_ids():
		var pawn := PawnFactory.make_starter_pawn(class_id, &"p", "p")
		for piece in [pawn.weapon, pawn.armor, pawn.accessory]:
			if piece == null:
				continue
			assert_true(piece.allows_class(pawn.pawn_class),
				"%s starts with %s and could not equip it" % [class_id, piece.id])


## Why issue 226 dressed the Abomination in a Gown and not in something chosen:
## the tags leave it one legal piece, so that entry is forced and moves the day
## an ANTI_SUPPORT or MAGICAL MELEE armour is added.
func test_the_abomination_has_exactly_one_armour_it_may_wear() -> void:
	var offered := _offered(ClassLibrary.get_class_def(&"abomination"), EquipmentDef.Slot.ARMOR)
	assert_eq(offered, [&"gown"] as Array[StringName],
		"the Abomination's armour is no longer forced, so PawnFactory's comment is now false")


func _offered(c: ClassDef, slot: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Registry.all_equipment_ids():
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

func _slot_name(slot: int) -> String:
	return ["weapon", "armor", "accessory"][slot]
