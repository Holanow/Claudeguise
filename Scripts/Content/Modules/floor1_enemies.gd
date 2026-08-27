extends RefCounted


## Floor 1's bestiary: monsters, not mirrors of the five pawn classes.

static func classes() -> Array[ClassDef]:
	return []

static func actions() -> Array[ActionDef]:
	return []

static func enemies() -> Array[EnemyDef]:
	## hp, damage, move, resist, action speed -- every one a multiple of
	## `MonsterProfile`. The absolutes these replaced are frozen in
	## `Tests/test_content_monster_profile.gd`; issue 542 changed where the
	## numbers come from and none of the numbers themselves.
	return [
		_enemy(&"goblin", "Goblin", 0.35, 0.9, 1.0, 0.0, 1.0, 16.5, CG.DamageType.PHYSICAL, [&"goblin_stab"], ["Melee", "Weak"], 0.7),
		_enemy(&"goblin_archer", "Goblin Archer", 0.28, 0.8, 0.8, 0.0, 1.0, 16.5, CG.DamageType.PHYSICAL, [&"goblin_arrow"], ["Ranged", "Weak"], 0.6),
		_enemy(&"ghoul", "Ghoul", 2.0, 2.0, 0.4, 0.4, 1.0, 24.0, CG.DamageType.PHYSICAL, [&"ghoul_maul"], ["Melee", "Undead", "Tough"], 0.1),
		_enemy(&"cultist", "Cultist", 0.5, 1.1, 0.75, 0.0, 1.0, 18.0, CG.DamageType.PROFANE, [&"cultist_bolt"], ["Ranged", "Profane"], 0.4),

		## 0.2x resistance, UNDER the Ghoul's 0.4x and the Brute's 0.6x. The
		## floor boss is the least armoured of the three tough monsters. Issue
		## 542 reports it and deliberately does not change it.
		_enemy(&"the_warden", "The Warden", 10.0, 5.8, 0.35, 0.2, 1.0, 33.0, CG.DamageType.PHYSICAL, [&"warden_axe", &"warden_chain_toss"], ["Melee", "Ranged", "Boss"], 0.0),

		## **Issue #121, the player's "big heavy guy that stuns units and taunts".
		_enemy(&"brute", "Brute", 3.2, 2.4, 0.45, 0.6, 1.0, 27.0, CG.DamageType.PHYSICAL, [&"brute_slam", &"brute_roar"], ["Melee", "Tough", "Stun", "Taunt"], 0.0),

		_enemy(&"stalker", "Stalker", 0.3, 0.5, 0.95, 0.0, 1.0, 15.0, CG.DamageType.PHYSICAL, [&"stalker_mark", &"stalker_dart"], ["Ranged", "Weak", "Support"], 0.5),

		## Issue 592: 0.4x, not 0.2x. A 20 hp rat died before it could be read;
		## 40 puts it level with the Goblin and under the Cultist's 0.5x.
		_enemy(&"rat", "Rat", 0.4, 0.3, 1.25, 0.0, 1.0, 12.0, CG.DamageType.PHYSICAL, [&"rat_bite"], ["Melee", "Weak", "Bleed"], 0.8),

		_enemy(&"rat_king", "The Rat King", 4.2, 2.1, 0.3, 0.0, 1.0, 36.0, CG.DamageType.PHYSICAL, [&"rat_king_lash"], ["Ranged", "Miniboss", "Summoner"], 0.0),
	]

static func encounters() -> Array[Encounter]:
	return []

static func items() -> Array[EquipmentDef]:
	return []

## Issue 542: multiples of `MonsterProfile`, not absolutes. `damage_type` is the
## one type this monster's attack power is expressed in; `radius` stays absolute
## because it is collision geometry rather than a stat.
static func _enemy(id: StringName, display_name: String, hp_mult: float, damage_mult: float, move_mult: float, resist_mult: float, action_speed: float, radius: float, damage_type: CG.DamageType, actions: Array[StringName], display_tags: Array[String], focus_bias: float = 0.0, resource_max: int = 0, resource_kind: CG.ResourceKind = CG.ResourceKind.ENERGY) -> EnemyDef:
	var e := EnemyDef.new()
	e.id = id
	e.display_name = display_name
	e.hp_max = MonsterProfile.hp(hp_mult)
	e.resource_max = resource_max
	e.resource_kind = resource_kind
	e.move_speed = MonsterProfile.move_speed(move_mult)
	e.radius = radius
	e.attack_power = {damage_type: MonsterProfile.damage(damage_mult)}
	e.damage_reduction = MonsterProfile.resistance(resist_mult)
	e.action_speed = action_speed
	e.actions = actions
	e.display_tags = display_tags
	e.focus_bias = focus_bias
	return e
