extends RefCounted


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
		_weapon(&"sword", "Sword", "A straight blade. Increases STR by 15%, and its wielder attacks with a Strike.", {CG.Attribute.STR: 0.15}, [CG.Method.MARTIAL], [&"warrior_strike"]),
		# Melee + Summoner. siege_master's own class is Ranged/Summoner in
		_weapon(&"wrench", "Wrench", "A heavy spanner. Increases DEX by 12% and STR by 5%, and its wielder attacks with a Strike.", {CG.Attribute.DEX: 0.12, CG.Attribute.STR: 0.05}, [CG.Method.MARTIAL], [&"warrior_strike"]),
		# Melee + Magical. abomination.
		_weapon(&"sickle", "Sickle", "A curved, filthy blade. Increases INT by 15%, and its wielder attacks with a poisoning Claw.", {CG.Attribute.INT: 0.15}, [CG.Method.MAGICAL], [&"abomination_claw"]),
		# Ranged + Magical. geysermancer.
		_weapon(&"orb", "Orb", "A sphere of trapped water. Increases INT by 18%, and its wielder attacks with a Spout.", {CG.Attribute.INT: 0.18}, [CG.Method.MAGICAL], [&"geyser_spout"]),
		# Ranged + Martial. siege_master. Issue 129: the player asked for a bow
		_weapon(&"bow", "Bow", "A recurve bow. Increases DEX by 15%, and its wielder attacks with a Shot at range.", {CG.Attribute.DEX: 0.15}, [CG.Method.MARTIAL], [&"siege_master_shot"]),
		# Ranged + Magical. priest. Issue 129: the player asked for a staff by
		_weapon(&"staff", "Staff", "A long carved stave. Increases INT by 12%, and its wielder attacks with a Bolt at range.", {CG.Attribute.INT: 0.12}, [CG.Method.MAGICAL], [&"priest_bolt"]),

		# --- Armor: flat, occasional CON percent, per README -------------
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
