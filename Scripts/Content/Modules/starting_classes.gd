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
		## CON 8->10 (issue 24, history only, superseded below). AGI 2->8,
		## CON 10->12, INT 7->12 (issue 37): the leave-one-out ablation showed
		## the party missing this class (no_abomination) as the best in the
		## game, 19/20, and the party missing the Siege Master as the worst,
		## 0/20 -- same three other classes both times. Traced with
		## Tools/WhyNoDamage.gd: this class fired only 5 actions across a
		## whole fight against a Siege Master's 22, mostly spent closing the
		## ~500-unit gap to its own 45-range melee kit at a crawl (AGI 2).
		## AGI raised so it actually reaches the fight; INT raised (this is a
		## MAGICAL class, so INT drives its attack power per Balance.gd) so
		## the actions it does land matter; CON raised alongside so more
		## uptime doesn't just mean dying faster. Landed at this combination
		## after several rounds against all five real parties in
		## Tools/SampleFights.gd: pushing INT alone to 15 fixed the bottom row
		## but inflated the three middle parties past their own coin-flip
		## bands (16-17/20); this split gets three of the five into a genuine
		## 11-13/20 coin flip without any party hitting 20/20, but does not
		## fully clear issue 37's 4-6 target for the Siege-Master-less party
		## (measured 1/20) -- disclosed on the board rather than forced.
		_class(
			&"abomination", "Abomination",
			CG.Method.MAGICAL, CG.Style.MELEE, CG.Role.ANTI_SUPPORT, CG.Role.TANK,
			[CG.DamageType.PROFANE, CG.DamageType.FIRE],
			CG.ResourceKind.RAGE,
			{CG.Attribute.STR: 5, CG.Attribute.DEX: 1, CG.Attribute.AGI: 8, CG.Attribute.CON: 12, CG.Attribute.INT: 12, CG.Attribute.ATN: 3, CG.Attribute.WIS: 4},
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
