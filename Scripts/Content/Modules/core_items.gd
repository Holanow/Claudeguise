extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")

## Base equipment types. README.md's own tables, filtered to the tag
## combinations the five starting classes actually carry -- a Bow (Ranged +
## Martial) has no class to fit yet, so it is not here; adding one is a new
## entry, not a rewrite of this file's shape. See Registry.gd for the module
## contract. OWNER: teal.
##
## Issue 39: weapons and accessories are percent per README ("directly
## increase a pawn's Str, Int, and/or Dex by a percentage" / "increase AGI,
## ATT, or INT by a percentage"), armor is flat plus an occasional CON
## percent ("increase a pawn's stats by a flat amount and occasionally their
## CON by a percentage"). `Balance.attribute()` is what actually applies
## these; this file only declares the numbers.
##
## `allowed_methods` (issue 40) is the tag-gating field, and it is populated
## on every weapon. It speaks martial-versus-magical only, which is the axis
## that makes a caster in plate wrong; README also gates by role and damage
## type, and nothing here enforces those. Per `EquipmentDef`'s own note,
## declaring is content's job and refusing is the equip screen's -- the screen
## should never offer a piece a pawn cannot use, so the player meets it as an
## absence rather than an error.
##
## Issue 100: `granted_actions` was empty on all seventeen items until
## `plate_mail` carried Directional Block. That field existing and no item
## using it is why equipment counted as unreachable.

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
		# Issue 40: allowed_methods set on every weapon -- this is the exact
		# "caster in plate"-shaped mismatch the field exists for, a Warrior
		# with an Orb or a Priest with a Sword. Armor and accessories are
		# gated by role/damage-type per README, which this field does not
		# reach (rook's own scope note), so they stay unrestricted.
		#
		# Melee + Martial. warrior.
		_weapon(&"sword", "Sword", "Increases STR by 15%.", {CG.Attribute.STR: 0.15}, [CG.Method.MARTIAL]),
		# Melee + Summoner. siege_master's own class is Ranged/Summoner in
		# practice (siege_shot, siege_barrage are both ranged), but README
		# gates Wrench on Melee+Summoner tags specifically; kept as the
		# closest base type to the class's Martial+Summoner combination
		# rather than inventing a sixth weapon type for one class.
		_weapon(&"wrench", "Wrench", "Increases DEX by 12% and STR by 5%.", {CG.Attribute.DEX: 0.12, CG.Attribute.STR: 0.05}, [CG.Method.MARTIAL]),
		# Melee + Magical. abomination.
		_weapon(&"sickle", "Sickle", "Increases INT by 15%.", {CG.Attribute.INT: 0.15}, [CG.Method.MAGICAL]),
		# Ranged + Magical. priest, geysermancer.
		_weapon(&"orb", "Orb", "Increases INT by 18%.", {CG.Attribute.INT: 0.18}, [CG.Method.MAGICAL]),

		# --- Armor: flat, occasional CON percent, per README -------------
		# Tank.
		# Issue 100: the first granted action in the game, and the whole point
		# of the issue -- `granted_actions` had been on `EquipmentDef` since
		# issue 39 with every one of the seventeen items leaving it empty, so
		# nothing had ever proved the field reaches a fight.
		#
		# Block rather than a new action, because README's own armor table
		# already says `Plate Mail | Tank | Block` -- this ability was always
		# meant to come from armor. Issue 99 takes it off the Warrior class at
		# the same time, so it does not exist in two places at once: a Warrior
		# now gets Directional Block by *wearing plate*, not by being a Warrior.
		#
		# `allowed_methods` deliberately left empty, so any class may wear it.
		# README gates armor by role (`Tank`) and `allowed_methods` only speaks
		# martial-versus-magical, so gating here would say something the design
		# does not -- the Abomination is a Tank and is MAGICAL. Per
		# `EquipmentDef.allowed_methods`'s own note, an item nobody has a reason
		# to refuse should not carry a restriction that means the wrong thing.
		_armor(&"plate_mail", "Plate Mail", "Heavy plate. Adds 2 CON, increases CON by 10%, absorbs 5% of every hit, and teaches its wearer to raise a Directional Block.", {CG.Attribute.CON: 2}, {CG.Attribute.CON: 0.10}, 0.05, [&"warrior_block"]),
		# DPS.
		_armor(&"silk_wraps", "Silk Wraps", "Adds 2 AGI.", {CG.Attribute.AGI: 2}, {}, 0.0),
		# Support.
		_armor(&"robes", "Robes", "Adds 2 WIS and absorbs 2% of every hit.", {CG.Attribute.WIS: 2}, {}, 0.02),
		# Anti-Support.
		_armor(&"gown", "Gown", "Adds 2 ATN and absorbs 2% of every hit.", {CG.Attribute.ATN: 2}, {}, 0.02),
		# Healer.
		_armor(&"scrubs", "Scrubs", "Adds 1 INT and 1 WIS.", {CG.Attribute.INT: 1, CG.Attribute.WIS: 1}, {}, 0.0),

		# --- Accessories: AGI/ATN/INT percent, per README -----------------
		# One per damage type the five starting classes actually carry.
		_accessory(&"whetstone", "Whetstone", "Increases AGI by 10%.", {CG.Attribute.AGI: 0.10}),
		_accessory(&"brown_ring", "Brown Ring", "Increases ATN by 10%.", {CG.Attribute.ATN: 0.10}),
		_accessory(&"red_ring", "Red Ring", "Increases AGI by 12%.", {CG.Attribute.AGI: 0.12}),
		_accessory(&"blue_ring", "Blue Ring", "Increases INT by 10%.", {CG.Attribute.INT: 0.10}),
		_accessory(&"yellow_ring", "Yellow Ring", "Increases ATN by 12%.", {CG.Attribute.ATN: 0.12}),
		_accessory(&"censer", "Censer", "Increases INT by 12%.", {CG.Attribute.INT: 0.12}),
		_accessory(&"fetish", "Fetish", "Increases ATN by 14%.", {CG.Attribute.ATN: 0.14}),
		_accessory(&"piece_of_nothing", "Piece of Nothing", "Increases AGI, ATN, and INT by 8% each.", {CG.Attribute.AGI: 0.08, CG.Attribute.ATN: 0.08, CG.Attribute.INT: 0.08}),
	]

static func _weapon(id: StringName, display_name: String, description: String, attribute_percent: Dictionary, allowed_methods: Array[CG.Method] = []) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.WEAPON
	e.attribute_percent = attribute_percent
	e.allowed_methods = allowed_methods
	return e

static func _armor(id: StringName, display_name: String, description: String, attribute_flat: Dictionary, attribute_percent: Dictionary, damage_reduction: float, granted_actions: Array[StringName] = []) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.ARMOR
	e.attribute_flat = attribute_flat
	e.attribute_percent = attribute_percent
	e.damage_reduction = damage_reduction
	e.granted_actions = granted_actions
	return e

static func _accessory(id: StringName, display_name: String, description: String, attribute_percent: Dictionary) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.ACCESSORY
	e.attribute_percent = attribute_percent
	return e
