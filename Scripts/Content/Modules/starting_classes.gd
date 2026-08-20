extends RefCounted


## The five README classes: Warrior, Priest, Geysermancer, Siege Master,
## Abomination. Attribute spreads are original tuning, not a transcription of
## README.md: the table there ships with the attribute columns blank on

static func classes() -> Array[ClassDef]:
	return [
		_class(
			&"warrior", "Warrior",
			CG.Method.MARTIAL, CG.Style.MELEE, CG.Role.TANK, CG.Role.DPS,
			[CG.DamageType.PHYSICAL, CG.DamageType.EARTH],
			CG.ResourceKind.RAGE,
			# Issue 30, second pass: CON 9->14. rook's own framing after
			# measuring the first pass -- "a taunting Warrior that dies
			# inside its own taunt window is a worse tank than one that
			{CG.Attribute.STR: 9, CG.Attribute.DEX: 2, CG.Attribute.AGI: 5, CG.Attribute.CON: 14, CG.Attribute.INT: 1, CG.Attribute.ATN: 1, CG.Attribute.WIS: 10},
			# Issue 99: warrior_block left this list for `plate_mail`, where
			# README's own armor table always had it, and warrior_second_wind
			# took its place.
			[&"warrior_guard", &"warrior_execute", &"warrior_taunt", &"warrior_second_wind"]
		),
		_class(
			&"priest", "Priest",
			CG.Method.MAGICAL, CG.Style.RANGED, CG.Role.HEALER, CG.Role.SUPPORT,
			[CG.DamageType.DIVINE, CG.DamageType.AIR],
			CG.ResourceKind.MANA,
			# WIS 5->8: two new preset plans (priest_haste, priest_ward, the
			# player's own "one for speed, one for resistance" direction) at
			# 2 blocks each, on top of the existing 2 plans' own 4 -- 8
			# blocks total, and Balance.plan_block_budget == WIS. Same "pure
			# capacity increase, not a power change" reasoning as the
			# Warrior's own WIS 4->6 for a third plan (issue 52): WIS has no
			# combat-stat side effect per README, it only governs plan length.
			{CG.Attribute.STR: 1, CG.Attribute.DEX: 2, CG.Attribute.AGI: 4, CG.Attribute.CON: 3, CG.Attribute.INT: 8, CG.Attribute.ATN: 7, CG.Attribute.WIS: 8},
			# Issue 129: priest_bolt leaves this list for the Staff. Smite is
			# the Priest's own ranged spell and stays; the free bolt was only
			# ever here because something had to be affordable when Mana ran
			[&"priest_heal", &"priest_smite", &"priest_haste", &"priest_ward"]
		),
		_class(
			&"geysermancer", "Geysermancer",
			CG.Method.MAGICAL, CG.Style.RANGED, CG.Role.DPS, CG.Role.SUPPORT,
			[CG.DamageType.WATER, CG.DamageType.FIRE],
			CG.ResourceKind.MANA,
			# Issue 79: WIS 4->6. Two plans at 2 blocks each sat exactly at
			# the WIS-4 budget, and this class needs a third (see
			# PresetPlans.gd: the Blast/Scald ladder is what makes Scald
			# reachable at all). Same pure-capacity reasoning as the
			# Warrior's 6->8 above and the Priest's 5->8 before it.
			{CG.Attribute.STR: 1, CG.Attribute.DEX: 3, CG.Attribute.AGI: 4, CG.Attribute.CON: 3, CG.Attribute.INT: 8, CG.Attribute.ATN: 7, CG.Attribute.WIS: 6},
			# Issue 129: geyser_spout leaves this list for the Orb. It was
			# added in issue 79 so a Geysermancer out of Mana had something
			# affordable to fall back to; the Orb is what supplies that now.
				[&"geyser_blast", &"geyser_scald", &"geyser_cleanse"]
		),
		## Issue 12: rebuilt as spotter/engineer, per the player's own spec.
		## `Style.SUMMONER` was on the class card while it played as pure
		## artillery (siege_shot at 260 range, past every enemy's own reach
		_class(
			&"siege_master", "Siege Master",
			CG.Method.MARTIAL, CG.Style.SUMMONER, CG.Role.DPS, CG.Role.ANTI_SUPPORT,
			[CG.DamageType.PHYSICAL, CG.DamageType.RAW],
			CG.ResourceKind.MANA,
			{CG.Attribute.STR: 3, CG.Attribute.DEX: 9, CG.Attribute.AGI: 5, CG.Attribute.CON: 4, CG.Attribute.INT: 2, CG.Attribute.ATN: 2, CG.Attribute.WIS: 4},
			# Issue 129: siege_master_shot leaves this list for the Bow. Note
			# what is left: `spotter_mark` does deal damage (power_scale 1.0),
			# so an unarmed Siege Master is not inert -- it marks, at 15 Mana a
			# time, and its engines still fire. It is simply much worse, which
			# is the point of holding a weapon.
			[&"spotter_mark", &"build_siege_engine"]
		),
		## CON 8->10 (issue 24, history only, superseded below). AGI 2->8,
		## CON 10->12, INT 7->12 (issue 37): the leave-one-out ablation showed
		## the party missing this class (no_abomination) as the best in the
		_class(
			&"abomination", "Abomination",
			CG.Method.MAGICAL, CG.Style.MELEE, CG.Role.ANTI_SUPPORT, CG.Role.TANK,
			[CG.DamageType.PROFANE, CG.DamageType.FIRE],
			CG.ResourceKind.RAGE,
			# Issue 206: WIS 4 -> 6, for a third plan and nothing else. Pure
			# capacity -- WIS has no combat-stat effect per README, it only
			# governs plan length, the same reasoning as the Warrior's 6->8
			{CG.Attribute.STR: 5, CG.Attribute.DEX: 1, CG.Attribute.AGI: 8, CG.Attribute.CON: 12, CG.Attribute.INT: 12, CG.Attribute.ATN: 3, CG.Attribute.WIS: 8},
			# Issue 129: abomination_claw leaves this list for the Sickle. Rage
			# only fills from a landed hit and both actions left here cost
			# Rage, so this is the class the weapon matters most to: an unarmed
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
	c.base_attributes = base_attributes
	c.starting_actions = starting_actions
	return c
