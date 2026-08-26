extends RefCounted



static func classes() -> Array[ClassDef]:
	return [
		_class(
			&"warrior", "Warrior",
			CG.Method.MARTIAL, CG.Style.MELEE, CG.Role.TANK, CG.Role.DPS,
			[CG.DamageType.PHYSICAL, CG.DamageType.EARTH],
			CG.ResourceKind.RAGE,
			{CG.Attribute.STR: 9, CG.Attribute.DEX: 2, CG.Attribute.AGI: 5, CG.Attribute.CON: 14, CG.Attribute.INT: 1, CG.Attribute.ATN: 1, CG.Attribute.WIS: 10},
			[&"warrior_guard", &"warrior_taunt", &"warrior_second_wind"]
		),
		_class(
			&"priest", "Priest",
			CG.Method.MAGICAL, CG.Style.RANGED, CG.Role.HEALER, CG.Role.SUPPORT,
			[CG.DamageType.DIVINE, CG.DamageType.AIR],
			CG.ResourceKind.MANA,
			## Issue 556: ATN is the resource lever at 8 a point, so the Priest's
			## pool comes from there and its INT never moves, because heals read
			## attack power and attack power for a MAGICAL pawn reads INT.
			{CG.Attribute.STR: 1, CG.Attribute.DEX: 0, CG.Attribute.AGI: 4, CG.Attribute.CON: 3, CG.Attribute.INT: 8, CG.Attribute.ATN: 9, CG.Attribute.WIS: 8},
			[&"priest_heal", &"priest_smite", &"priest_haste", &"priest_ward", &"channel_mana"]
		),
		_class(
			&"geysermancer", "Geysermancer",
			CG.Method.MAGICAL, CG.Style.RANGED, CG.Role.DPS, CG.Role.SUPPORT,
			[CG.DamageType.WATER, CG.DamageType.FIRE],
			CG.ResourceKind.MANA,
			## Issue 556: INT is the damage lever and AGI the movement one, and the
			## 2 hp the Priest is "slightly" ahead by is this STR rather than a
			## point of CON, which would be 12.
			{CG.Attribute.STR: 0, CG.Attribute.DEX: 0, CG.Attribute.AGI: 6, CG.Attribute.CON: 3, CG.Attribute.INT: 10, CG.Attribute.ATN: 7, CG.Attribute.WIS: 6},
				[&"geyser_blast", &"geyser_scald", &"geyser_cleanse", &"channel_mana"]
		),
		## Issue 12: rebuilt as spotter/engineer, per the player's own spec.
		_class(
			&"siege_master", "Siege Master",
			CG.Method.MARTIAL, CG.Style.SUMMONER, CG.Role.DPS, CG.Role.ANTI_SUPPORT,
			[CG.DamageType.PHYSICAL, CG.DamageType.RAW],
			CG.ResourceKind.MANA,
			{CG.Attribute.STR: 3, CG.Attribute.DEX: 9, CG.Attribute.AGI: 5, CG.Attribute.CON: 4, CG.Attribute.INT: 2, CG.Attribute.ATN: 2, CG.Attribute.WIS: 4},
			[&"spotter_mark", &"build_siege_engine"]
		),
		_class(
			&"abomination", "Abomination",
			CG.Method.MAGICAL, CG.Style.MELEE, CG.Role.ANTI_SUPPORT, CG.Role.TANK,
			[CG.DamageType.PROFANE, CG.DamageType.FIRE],
			CG.ResourceKind.RAGE,
			{CG.Attribute.STR: 5, CG.Attribute.DEX: 1, CG.Attribute.AGI: 8, CG.Attribute.CON: 12, CG.Attribute.INT: 12, CG.Attribute.ATN: 3, CG.Attribute.WIS: 8},
			[&"abomination_hook", &"abomination_grapple", &"abomination_immolate"]
		),
	]

static func actions() -> Array[ActionDef]:
	return []

static func enemies() -> Array[EnemyDef]:
	return []

static func encounters() -> Array[Encounter]:
	return []

static func items() -> Array[EquipmentDef]:
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
	var attrs := {}
	for k in base_attributes:
		attrs[ClassDef.ATTRIBUTE_NAME[k]] = base_attributes[k]
	c.base_attributes = attrs
	var acts: Array[ActionDef] = []
	for a in starting_actions:
		acts.append(load("res://Scripts/Content/Actions/%s.tres" % a))
	c.starting_actions = acts
	return c
