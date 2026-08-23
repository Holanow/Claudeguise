extends RefCounted


## Base equipment types, filtered to the tag combinations the five starting
## classes carry. See Registry.gd for the module contract. OWNER: teal.
static func classes() -> Array[ClassDef]:
	return []

static func actions() -> Array[ActionDef]:
	return []

static func enemies() -> Array[EnemyDef]:
	return []

static func encounters() -> Array[Encounter]:
	return []

static func items() -> Array[EquipmentDef]:
	return [
		# --- Weapons: Str/Int/Dex percent, per README's advanced tier -----
		_weapon(&"sword", "Sword", "A straight blade. Increases STR by 15%, and its wielder attacks with a Strike.", {CG.Attribute.STR: 0.15}, [CG.Tag.MARTIAL], [&"warrior_strike"]),
		_weapon(&"wrench", "Wrench", "A heavy spanner. Increases DEX by 12% and STR by 5%, and its wielder attacks with a Strike.", {CG.Attribute.DEX: 0.12, CG.Attribute.STR: 0.05}, [CG.Tag.MARTIAL], [&"warrior_strike"]),
		## The Claw it grants reaches 45 units, so a ranged caster holding this
		## has no basic attack it can use. MELEE describes the weapon rather
		## than expressing a preference about who deserves it.
		_weapon(&"sickle", "Sickle", "A curved, filthy blade. Increases INT by 15%, and its wielder attacks with a poisoning Claw.", {CG.Attribute.INT: 0.15}, [CG.Tag.MAGICAL, CG.Tag.MELEE], [&"abomination_claw"]),
		_weapon(&"orb", "Orb", "A sphere of trapped water. Increases INT by 18%, and its wielder attacks with a Spout.", {CG.Attribute.INT: 0.18}, [CG.Tag.MAGICAL], [&"geyser_spout"]),
		_weapon(&"bow", "Bow", "A recurve bow. Increases DEX by 15%, and its wielder attacks with a Shot at range.", {CG.Attribute.DEX: 0.15}, [CG.Tag.MARTIAL], [&"siege_master_shot"]),
		_weapon(&"staff", "Staff", "A long carved stave. Increases INT by 12%, and its wielder attacks with a Bolt at range.", {CG.Attribute.INT: 0.12}, [CG.Tag.MAGICAL], [&"priest_bolt"]),

		# --- Armor: flat, occasional CON percent, per README -------------
		## Issue 131: the role each of these was written for sat in a comment
		## here and was enforced nowhere. It is the tag list now, so the two
		## cannot drift apart.
		_armor(&"plate_mail", "Plate Mail", "Heavy plate. Adds 2 CON, increases CON by 10%, absorbs 5% of every hit, and teaches its wearer to raise a Directional Block.", {CG.Attribute.CON: 2}, {CG.Attribute.CON: 0.10}, 0.05, [CG.Tag.MARTIAL, CG.Tag.TANK], [&"warrior_block"]),
		_armor(&"silk_wraps", "Silk Wraps", "Adds 2 AGI.", {CG.Attribute.AGI: 2}, {}, 0.0, [CG.Tag.DPS]),
		_armor(&"robes", "Robes", "Adds 2 WIS and absorbs 2% of every hit.", {CG.Attribute.WIS: 2}, {}, 0.02, [CG.Tag.SUPPORT]),
		_armor(&"gown", "Gown", "Adds 2 ATN and absorbs 2% of every hit.", {CG.Attribute.ATN: 2}, {}, 0.02, [CG.Tag.ANTI_SUPPORT]),
		_armor(&"scrubs", "Scrubs", "Adds 1 INT and 1 WIS.", {CG.Attribute.INT: 1, CG.Attribute.WIS: 1}, {}, 0.0, [CG.Tag.HEALER]),

		# --- Accessories: AGI/ATN/INT percent, per README -----------------
		## One per damage type the five starting classes actually carry. Only
		## the two whose whole bonus is INT are tagged: INT is the attack stat
		## for MAGICAL classes and for nobody else, so that restriction
		## describes the item instead of inventing a rule for it.
		_accessory(&"whetstone", "Whetstone", "Increases AGI by 10%.", {CG.Attribute.AGI: 0.10}),
		_accessory(&"brown_ring", "Brown Ring", "Increases ATN by 10%.", {CG.Attribute.ATN: 0.10}),
		_accessory(&"red_ring", "Red Ring", "Increases AGI by 12%.", {CG.Attribute.AGI: 0.12}),
		_accessory(&"blue_ring", "Blue Ring", "Increases INT by 10%.", {CG.Attribute.INT: 0.10}, [CG.Tag.MAGICAL]),
		_accessory(&"yellow_ring", "Yellow Ring", "Increases ATN by 12%.", {CG.Attribute.ATN: 0.12}),
		_accessory(&"censer", "Censer", "Increases INT by 12%.", {CG.Attribute.INT: 0.12}, [CG.Tag.MAGICAL]),
		_accessory(&"fetish", "Fetish", "Increases ATN by 14%.", {CG.Attribute.ATN: 0.14}),
		_accessory(&"piece_of_nothing", "Piece of Nothing", "Increases AGI, ATN, and INT by 8% each.", {CG.Attribute.AGI: 0.08, CG.Attribute.ATN: 0.08, CG.Attribute.INT: 0.08}),
	]

static func _weapon(id: StringName, display_name: String, description: String, attribute_percent: Dictionary, required_tags: Array[int] = [], granted_actions: Array[StringName] = []) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.WEAPON
	e.attribute_percent = attribute_percent
	e.required_tags = required_tags
	e.granted_actions = granted_actions
	return e

static func _armor(id: StringName, display_name: String, description: String, attribute_flat: Dictionary, attribute_percent: Dictionary, damage_reduction: float, required_tags: Array[int] = [], granted_actions: Array[StringName] = []) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.ARMOR
	e.required_tags = required_tags
	e.attribute_flat = attribute_flat
	e.attribute_percent = attribute_percent
	e.damage_reduction = damage_reduction
	e.granted_actions = granted_actions
	return e

static func _accessory(id: StringName, display_name: String, description: String, attribute_percent: Dictionary, required_tags: Array[int] = []) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.ACCESSORY
	e.required_tags = required_tags
	e.attribute_percent = attribute_percent
	return e
