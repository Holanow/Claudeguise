extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")

## The five README classes: Warrior, Priest, Geysermancer, Siege Master,
## Abomination. Attribute spreads are original tuning, not a transcription of
## README.md: the table there ships with the attribute columns blank on
## purpose. See Registry.gd for the module contract. OWNER: teal.

static func classes() -> Array[ClassDef]:
	return [
		_class(
			&"warrior", "Warrior",
			CG.Method.MARTIAL, CG.Style.MELEE, CG.Role.TANK, CG.Role.DPS,
			[CG.DamageType.PHYSICAL, CG.DamageType.EARTH],
			CG.ResourceKind.RAGE,
			{CG.Attribute.STR: 9, CG.Attribute.DEX: 2, CG.Attribute.AGI: 5, CG.Attribute.CON: 9, CG.Attribute.INT: 1, CG.Attribute.ATN: 1, CG.Attribute.WIS: 4},
			[&"warrior_strike", &"warrior_guard", &"warrior_execute"]
		),
		_class(
			&"priest", "Priest",
			CG.Method.MAGICAL, CG.Style.RANGED, CG.Role.HEALER, CG.Role.SUPPORT,
			[CG.DamageType.DIVINE, CG.DamageType.AIR],
			CG.ResourceKind.MANA,
			{CG.Attribute.STR: 1, CG.Attribute.DEX: 2, CG.Attribute.AGI: 4, CG.Attribute.CON: 3, CG.Attribute.INT: 8, CG.Attribute.ATN: 7, CG.Attribute.WIS: 5},
			[&"priest_heal", &"priest_smite"]
		),
		_class(
			&"geysermancer", "Geysermancer",
			CG.Method.MAGICAL, CG.Style.RANGED, CG.Role.DPS, CG.Role.SUPPORT,
			[CG.DamageType.WATER, CG.DamageType.FIRE],
			CG.ResourceKind.MANA,
			{CG.Attribute.STR: 1, CG.Attribute.DEX: 3, CG.Attribute.AGI: 4, CG.Attribute.CON: 3, CG.Attribute.INT: 8, CG.Attribute.ATN: 7, CG.Attribute.WIS: 4},
			[&"geyser_blast", &"geyser_scald"]
		),
		_class(
			&"siege_master", "Siege Master",
			CG.Method.MARTIAL, CG.Style.SUMMONER, CG.Role.DPS, CG.Role.ANTI_SUPPORT,
			[CG.DamageType.PHYSICAL, CG.DamageType.RAW],
			CG.ResourceKind.ENERGY,
			{CG.Attribute.STR: 3, CG.Attribute.DEX: 9, CG.Attribute.AGI: 5, CG.Attribute.CON: 4, CG.Attribute.INT: 2, CG.Attribute.ATN: 2, CG.Attribute.WIS: 4},
			[&"siege_shot", &"siege_barrage"]
		),
		_class(
			&"abomination", "Abomination",
			CG.Method.MAGICAL, CG.Style.MELEE, CG.Role.ANTI_SUPPORT, CG.Role.TANK,
			[CG.DamageType.PROFANE, CG.DamageType.FIRE],
			CG.ResourceKind.RAGE,
			{CG.Attribute.STR: 5, CG.Attribute.DEX: 1, CG.Attribute.AGI: 2, CG.Attribute.CON: 8, CG.Attribute.INT: 7, CG.Attribute.ATN: 3, CG.Attribute.WIS: 4},
			[&"abomination_claw", &"abomination_immolate"]
		),
	]

static func actions() -> Array[ActionDef]:
	return []

static func enemies() -> Array[EnemyDef]:
	return []

static func encounters() -> Array[Encounter]:
	return []

static func _class(id: StringName, display_name: String, method: CG.Method, style: CG.Style, role_primary: CG.Role, role_secondary: CG.Role, damage_types: Array, resource_kind: CG.ResourceKind, base_attributes: Dictionary, starting_actions: Array[StringName]) -> ClassDef:
	var c := ClassDef.new()
	c.id = id
	c.display_name = display_name
	c.method = method
	c.style = style
	c.role_primary = role_primary
	c.role_secondary = role_secondary
	var dts: Array[int] = []
	for d in damage_types:
		dts.append(int(d))
	c.damage_types = dts
	c.resource_kind = resource_kind
	c.base_attributes = base_attributes
	c.starting_actions = starting_actions
	return c
