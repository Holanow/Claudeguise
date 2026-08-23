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
		# --- Weapons: each grants the basic attack its wielder fights with ----
		_weapon(&"sword", "Sword", "A straight blade. Its wielder attacks with a Strike.", [CG.Tag.MARTIAL], [&"warrior_strike"]),
		_weapon(&"wrench", "Wrench", "A heavy spanner. Its wielder attacks with a Strike.", [CG.Tag.MARTIAL], [&"warrior_strike"]),
		## The Claw it grants reaches 45 units, so a ranged caster holding this
		## has no basic attack it can use. MELEE describes the weapon rather
		## than expressing a preference about who deserves it.
		_weapon(&"sickle", "Sickle", "A curved, filthy blade. Its wielder attacks with a poisoning Claw.", [CG.Tag.MAGICAL, CG.Tag.MELEE], [&"abomination_claw"]),
		_weapon(&"orb", "Orb", "A sphere of trapped water. Its wielder attacks with a Spout.", [CG.Tag.MAGICAL], [&"geyser_spout"]),
		_weapon(&"bow", "Bow", "A recurve bow. Its wielder attacks with a Shot at range.", [CG.Tag.MARTIAL], [&"siege_master_shot"]),
		_weapon(&"staff", "Staff", "A long carved stave. Its wielder attacks with a Bolt at range.", [CG.Tag.MAGICAL], [&"priest_bolt"]),

		# --- Armor: one grants an action, the rest grant plan rows -----------
		## Issue 489: gear grants Wisdom or an action and nothing else, so plate
		## is now the Directional Block and nothing but it. The trade that
		## creates is the point -- a Warrior picks between blocking and a row.
		_armor(&"plate_mail", "Plate Mail", "Heavy plate. Teaches its wearer to raise a Directional Block.", 0, [CG.Tag.MARTIAL, CG.Tag.TANK], [&"warrior_block"]),
		## One per role, because a class with no armour it may wear would have
		## no way to buy a plan row at all.
		_armor(&"silk_wraps", "Silk Wraps", "Light and quiet. Adds 2 Wisdom.", 2, [CG.Tag.DPS]),
		_armor(&"robes", "Robes", "Heavy cloth, well worn. Adds 2 Wisdom.", 2, [CG.Tag.SUPPORT]),
		_armor(&"gown", "Gown", "Layered and formal. Adds 2 Wisdom.", 2, [CG.Tag.ANTI_SUPPORT]),

		# --- Accessories -----------------------------------------------------
		## Issue 489 left every accessory empty; seven were deleted and this one
		## kept, because it is the only slot open to everyone. It is the extra
		## row a class takes when its armour is doing something else, which is
		## the Warrior in plate. Untagged: the MAGICAL tag it used to carry was
		## justified by its INT bonus and went with it.
		_accessory(&"censer", "Censer", "Smoke and slow thought. Adds 1 Wisdom.", 1),
	]

static func _weapon(id: StringName, display_name: String, description: String, required_tags: Array[int] = [], granted_actions: Array[StringName] = []) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.WEAPON
	e.required_tags = required_tags
	e.granted_actions = granted_actions
	return e

## Issue 489: wisdom and granted actions are the only two things a piece may
## carry, so there is no attribute dictionary and no damage reduction to pass.
static func _armor(id: StringName, display_name: String, description: String, wisdom: int, required_tags: Array[int] = [], granted_actions: Array[StringName] = []) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.ARMOR
	e.required_tags = required_tags
	if wisdom != 0:
		e.attribute_flat = {CG.Attribute.WIS: wisdom}
	e.granted_actions = granted_actions
	return e

static func _accessory(id: StringName, display_name: String, description: String, wisdom: int, required_tags: Array[int] = []) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.ACCESSORY
	e.required_tags = required_tags
	if wisdom != 0:
		e.attribute_flat = {CG.Attribute.WIS: wisdom}
	return e
