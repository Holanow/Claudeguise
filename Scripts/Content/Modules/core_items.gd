extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")

## Base equipment types. README.md's own tables, filtered to the tag
## combinations the five starting classes actually carry. This note used to say
## a Bow had no class to fit and was therefore absent; issue 129 added one (and
## a Staff), because a Siege Master is Martial and fights at range and a Bow is
## exactly what it was holding all along. See Registry.gd for the module
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
##
## Issue 129, the player's own instruction -- "a unit's basic attack should be
## determined by its main hand weapon rather than its class". README's weapon
## table has carried a **Provided Actions** column from the start (Sword ->
## Attack, Bow -> Ranged Attack, Orb -> Ranged Magical Attack) and no weapon
## here provided anything. Every weapon now grants exactly one basic attack,
## and `starting_classes.gd` no longer ships one.
##
## | Weapon | README tags     | Provides         |
## | ------ | --------------- | ---------------- |
## | Sword  | Melee, Martial  | Strike           |
## | Wrench | Melee, Summoner | Strike           |
## | Sickle | Melee, Magical  | Claw             |
## | Bow    | Ranged, Martial | Shot             |
## | Orb    | Ranged, Magical | Spout            |
## | Staff  | Ranged, Magical | Bolt             |
##
## **The five actions are the five each class used to carry, unchanged and not
## renamed.** The mapping is deliberately the identity one -- a Warrior with a
## Sword still swings Strike, a Priest with a Staff still casts Bolt -- so that
## the only thing this issue moves is *where the action comes from*, and the
## balance measurement is attributable to that and to the weapon's own
## percentages rather than to five new sets of numbers. Their ids keep their
## old class prefixes (`warrior_strike`, `priest_bolt`, ...) because renaming
## them would edit `Scripts/Art/ActionIcons.gd`, `Tests/test_art.gd`,
## `Tests/test_combat_sim.gd` and `Tests/test_ui_*` -- four files across two
## other sessions -- for no change a player can see. Worth its own issue, not
## worth taking someone else's fixtures hostage for this one.
##
## **Every weapon grants exactly one attack, and there is a test for it.** A
## weapon that granted nothing would be a trap: a pawn holding it has no free
## action at all and stands still whenever it cannot pay for a spell, which is
## the resource-exhaustion wall issues 22, 62 and 79 each fixed once. README
## lists Wrench as providing "Tag, Overcharge" -- neither mechanism exists --
## so it provides the plain melee attack instead of nothing.

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
		_weapon(&"sword", "Sword", "A straight blade. Increases STR by 15%, and its wielder attacks with a Strike.", {CG.Attribute.STR: 0.15}, [CG.Method.MARTIAL], [&"warrior_strike"]),
		# Melee + Summoner. siege_master's own class is Ranged/Summoner in
		# practice (siege_shot, siege_barrage are both ranged), but README
		# gates Wrench on Melee+Summoner tags specifically; kept as the
		# closest base type to the class's Martial+Summoner combination
		# rather than inventing a sixth weapon type for one class.
		_weapon(&"wrench", "Wrench", "A heavy spanner. Increases DEX by 12% and STR by 5%, and its wielder attacks with a Strike.", {CG.Attribute.DEX: 0.12, CG.Attribute.STR: 0.05}, [CG.Method.MARTIAL], [&"warrior_strike"]),
		# Melee + Magical. abomination.
		_weapon(&"sickle", "Sickle", "A curved, filthy blade. Increases INT by 15%, and its wielder attacks with a poisoning Claw.", {CG.Attribute.INT: 0.15}, [CG.Method.MAGICAL], [&"abomination_claw"]),
		# Ranged + Magical. geysermancer.
		_weapon(&"orb", "Orb", "A sphere of trapped water. Increases INT by 18%, and its wielder attacks with a Spout.", {CG.Attribute.INT: 0.18}, [CG.Method.MAGICAL], [&"geyser_spout"]),
		# Ranged + Martial. siege_master. Issue 129: the player asked for a bow
		# by name, and README's table has had one from the start with no class
		# whose tags fit it -- the note at the top of this file said as much.
		# The Siege Master is MARTIAL and fights at 200 units, so it fits now.
		# DEX because that is what `Balance.attack_power` reads for a Martial
		# class that is not Melee, the same relationship Sword has to STR.
		_weapon(&"bow", "Bow", "A recurve bow. Increases DEX by 15%, and its wielder attacks with a Shot at range.", {CG.Attribute.DEX: 0.15}, [CG.Method.MARTIAL], [&"siege_master_shot"]),
		# Ranged + Magical. priest. Issue 129: the player asked for a staff by
		# name. README's own table does not have one -- its Ranged+Magical entry
		# is the Orb -- so this is a second weapon of the same base tags rather
		# than a new tag combination, which is what lets the Priest and the
		# Geysermancer hold different things. The player is writing real items
		# into the design document later; this is not an attempt to guess that
		# table.
		_weapon(&"staff", "Staff", "A long carved stave. Increases INT by 12%, and its wielder attacks with a Bolt at range.", {CG.Attribute.INT: 0.12}, [CG.Method.MAGICAL], [&"priest_bolt"]),

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

static func _weapon(id: StringName, display_name: String, description: String, attribute_percent: Dictionary, allowed_methods: Array[CG.Method] = [], granted_actions: Array[StringName] = []) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = id
	e.display_name = display_name
	e.description = description
	e.slot = EquipmentDef.Slot.WEAPON
	e.attribute_percent = attribute_percent
	e.allowed_methods = allowed_methods
	e.granted_actions = granted_actions
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
