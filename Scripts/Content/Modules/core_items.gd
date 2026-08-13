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
## No tag-gating field exists on `EquipmentDef` yet -- it has id, slot,
## description, attribute_percent/flat, damage_reduction and
## granted_actions, and nothing that says which class may equip a given
## piece. Each item's doc comment below names the tag combination it targets
## per README's own tables, but nothing here refuses an equip that violates
## it; that is either a Core field to ask for or pike's equip screen to
## enforce, flagged on the board rather than guessed at here.

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
		_weapon(&"sword", "Sword", "A balanced blade. Hits harder the stronger its wielder already is.", {CG.Attribute.STR: 0.15}, [CG.Method.MARTIAL]),
		# Melee + Summoner. siege_master's own class is Ranged/Summoner in
		# practice (siege_shot, siege_barrage are both ranged), but README
		# gates Wrench on Melee+Summoner tags specifically; kept as the
		# closest base type to the class's Martial+Summoner combination
		# rather than inventing a sixth weapon type for one class.
		_weapon(&"wrench", "Wrench", "Built for leverage, not speed. Favours raw reach over finesse.", {CG.Attribute.DEX: 0.12, CG.Attribute.STR: 0.05}, [CG.Method.MARTIAL]),
		# Melee + Magical. abomination.
		_weapon(&"sickle", "Sickle", "Curved to follow through. Channels a caster's own force rather than steel.", {CG.Attribute.INT: 0.15}, [CG.Method.MAGICAL]),
		# Ranged + Magical. priest, geysermancer.
		_weapon(&"orb", "Orb", "A focus rather than a weapon. Amplifies whatever the caster already knows.", {CG.Attribute.INT: 0.18}, [CG.Method.MAGICAL]),

		# --- Armor: flat, occasional CON percent, per README -------------
		# Tank.
		_armor(&"plate_mail", "Plate Mail", "Heavy enough to matter. Absorbs a real fraction of every hit.", {CG.Attribute.CON: 2}, {CG.Attribute.CON: 0.10}, 0.05),
		# DPS.
		_armor(&"silk_wraps", "Silk Wraps", "Light and unobtrusive. Trades protection for not slowing anyone down.", {CG.Attribute.AGI: 2}, {}, 0.0),
		# Support.
		_armor(&"robes", "Robes", "Loose enough to move in, warm enough to matter in a long fight.", {CG.Attribute.WIS: 2}, {}, 0.02),
		# Anti-Support.
		_armor(&"gown", "Gown", "Unassuming. Nobody expects the one wearing it to be the threat.", {CG.Attribute.ATN: 2}, {}, 0.02),
		# Healer.
		_armor(&"scrubs", "Scrubs", "Practical rather than protective. Made for someone who plans to be busy.", {CG.Attribute.INT: 1, CG.Attribute.WIS: 1}, {}, 0.0),

		# --- Accessories: AGI/ATN/INT percent, per README -----------------
		# One per damage type the five starting classes actually carry.
		_accessory(&"whetstone", "Whetstone", "Keeps an edge sharp longer than it has any right to be.", {CG.Attribute.AGI: 0.10}),
		_accessory(&"brown_ring", "Brown Ring", "Sits heavy on the hand. Grounds whoever wears it.", {CG.Attribute.ATN: 0.10}),
		_accessory(&"red_ring", "Red Ring", "Warm to the touch, always. Quickens the hand that wears it.", {CG.Attribute.AGI: 0.12}),
		_accessory(&"blue_ring", "Blue Ring", "Cool and unhurried. Steadies rather than quickens.", {CG.Attribute.INT: 0.10}),
		_accessory(&"yellow_ring", "Yellow Ring", "Light as the element it channels. Sharpens reaction rather than force.", {CG.Attribute.ATN: 0.12}),
		_accessory(&"censer", "Censer", "Trails a thin smoke that seems to steady the wearer's focus.", {CG.Attribute.INT: 0.12}),
		_accessory(&"fetish", "Fetish", "Uncomfortable to hold, and it works better the longer it is carried anyway.", {CG.Attribute.ATN: 0.14}),
		_accessory(&"piece_of_nothing", "Piece of Nothing", "Weighs nothing, resists description. Amplifies whatever is already there.", {CG.Attribute.AGI: 0.08, CG.Attribute.ATN: 0.08, CG.Attribute.INT: 0.08}),
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

static func _armor(id: StringName, display_name: String, description: String, attribute_flat: Dictionary, attribute_percent: Dictionary, damage_reduction: float) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.ARMOR
	e.attribute_flat = attribute_flat
	e.attribute_percent = attribute_percent
	e.damage_reduction = damage_reduction
	return e

static func _accessory(id: StringName, display_name: String, description: String, attribute_percent: Dictionary) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.ACCESSORY
	e.attribute_percent = attribute_percent
	return e
