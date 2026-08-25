extends RefCounted


## Floor 1's bestiary: monsters, not mirrors of the five pawn classes.

static func classes() -> Array[ClassDef]:
	return []

## Ranged projectile speed. Duplicated from `core_actions.gd` rather than
## reached into: that file's copy is a `const` on another session's module and
## reading a neighbour's private constant is how two numbers start disagreeing
## silently. If issue 93's speed moves again, this moves with it, and the
## reason it is worth having twice is that a mark with no travel time cannot be
## shielded, dodged or seen coming.
const RANGED_PROJECTILE_SPEED := 32.5

static func actions() -> Array[ActionDef]:
	return [
		_action_taunt(&"brute_roar", "Roar", "Forces every enemy within 200 units to attack the Brute for 8 seconds. It cannot roar again for another 16 seconds.", 8, 9, 200.0, 120, 240),
		_action_status(&"brute_slam", "Slam", "A heavy melee blow at up to 50 units that stuns for 0.5 seconds, cancelling whatever the target was casting.", CG.DamageType.PHYSICAL, 50.0, 16, 18, 2.0, 0, CG.Status.STUN, 8),

		_projectile(_action_status_cd(&"stalker_mark", "Mark", "Marks a target within 220 units for 6 seconds, stripping its natural armour.", CG.DamageType.PHYSICAL, 220.0, 4, 5, 1.0, 0, CG.Status.MARKED, 90, 60, true), RANGED_PROJECTILE_SPEED),

		_projectile(_action(&"stalker_dart", "Dart", "A light ranged dart at up to 200 units.", CG.DamageType.PHYSICAL, 200.0, 6, 8, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),

		_action_status(&"rat_bite", "Bite", "A fast melee bite at up to 40 units that adds a stack of Bleed.", CG.DamageType.PHYSICAL, 40.0, 3, 4, 1.0, 0, CG.Status.BLEED, 45),

		_summons(_action(&"rat_king_lash", "Tail Lash", "A ranged strike at up to 200 units that leaves a rat behind.", CG.DamageType.PHYSICAL, 200.0, 20, 22, 1.0, 0, 0, true), &"rat"),
	]

static func enemies() -> Array[EnemyDef]:
	## hp, damage, move, resist, action speed -- every one a multiple of
	## `MonsterProfile`. The absolutes these replaced are frozen in
	## `Tests/test_content_monster_profile.gd`; issue 542 changed where the
	## numbers come from and none of the numbers themselves.
	return [
		_enemy(&"goblin", "Goblin", 0.35, 0.9, 1.0, 0.0, 1.0, 11.0, CG.DamageType.PHYSICAL, [&"goblin_stab"], ["Melee", "Weak"], 0.7),
		_enemy(&"goblin_archer", "Goblin Archer", 0.28, 0.8, 0.8, 0.0, 1.0, 11.0, CG.DamageType.PHYSICAL, [&"goblin_arrow"], ["Ranged", "Weak"], 0.6),
		_enemy(&"ghoul", "Ghoul", 2.0, 2.0, 0.4, 0.4, 1.0, 16.0, CG.DamageType.PHYSICAL, [&"ghoul_maul"], ["Melee", "Undead", "Tough"], 0.1),
		_enemy(&"cultist", "Cultist", 0.5, 1.1, 0.75, 0.0, 1.0, 12.0, CG.DamageType.PROFANE, [&"cultist_bolt"], ["Ranged", "Profane"], 0.4),

		## 0.2x resistance, UNDER the Ghoul's 0.4x and the Brute's 0.6x. The
		## floor boss is the least armoured of the three tough monsters. Issue
		## 542 reports it and deliberately does not change it.
		_enemy(&"the_warden", "The Warden", 10.0, 5.8, 0.35, 0.2, 1.0, 22.0, CG.DamageType.PHYSICAL, [&"warden_axe", &"warden_chain_toss"], ["Melee", "Ranged", "Boss"], 0.0),

		## **Issue #121, the player's "big heavy guy that stuns units and taunts".
		_enemy(&"brute", "Brute", 3.2, 2.4, 0.45, 0.6, 1.0, 18.0, CG.DamageType.PHYSICAL, [&"brute_slam", &"brute_roar"], ["Melee", "Tough", "Stun", "Taunt"], 0.0),

		_enemy(&"stalker", "Stalker", 0.3, 0.5, 0.95, 0.0, 1.0, 10.0, CG.DamageType.PHYSICAL, [&"stalker_mark", &"stalker_dart"], ["Ranged", "Weak", "Support"], 0.5),

		## Issue 592: 0.4x, not 0.2x. A 20 hp rat died before it could be read;
		## 40 puts it level with the Goblin and under the Cultist's 0.5x.
		_enemy(&"rat", "Rat", 0.4, 0.3, 1.25, 0.0, 1.0, 8.0, CG.DamageType.PHYSICAL, [&"rat_bite"], ["Melee", "Weak", "Bleed"], 0.8),

		_enemy(&"rat_king", "The Rat King", 4.2, 2.1, 0.3, 0.0, 1.0, 24.0, CG.DamageType.PHYSICAL, [&"rat_king_lash"], ["Ranged", "Miniboss", "Summoner"], 0.0),
	]

static func encounters() -> Array[Encounter]:
	return []

static func items() -> Array[EquipmentDef]:
	return []

## The two action helpers this module needs, and they are copies of
## `core_actions.gd`'s rather than calls into it. Those are `static func _`
static func _action(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int, requires_los: bool = false) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.display_name = display_name
	a.description = description
	a.damage_type = damage_type
	a.range_units = range_units
	a.wind_up_ticks = wind_up
	a.recover_ticks = recover
	a.power_scale = power_scale
	a.resource_cost = resource_cost
	a.cooldown_ticks = cooldown_ticks
	a.requires_line_of_sight = requires_los
	return a

static func _action_status(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, status: CG.Status, duration_ticks: int, requires_los: bool = false) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0, requires_los)
	a.applies_status_enabled = true
	a.applies_status = status
	a.status_duration_ticks = duration_ticks
	return a

## `_action_status` with a real cooldown. `core_actions.gd`'s version hardcodes
## `cooldown_ticks` to 0 and its own comment says so twice, which is right for
## every caller it has -- a damage-dealing status application whose rate is
## already limited by its wind-up. It is wrong for an action whose entire
## effect is a status that already lasts 90 ticks.
static func _action_status_cd(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, status: CG.Status, duration_ticks: int, cooldown_ticks: int, requires_los: bool = false) -> ActionDef:
	var a := _action_status(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, status, duration_ticks, requires_los)
	a.cooldown_ticks = cooldown_ticks
	return a

## Issue 150: an enemy's taunt. Self-targeted, no damage of its own -- the
## status is the whole effect, the shape `core_actions._action_taunt` already
## uses for the Warrior's.
static func _action_taunt(id: StringName, display_name: String, description: String, wind_up: int, recover: int, taunt_radius: float, duration_ticks: int, cooldown_ticks: int) -> ActionDef:
	var a := _action(id, display_name, description, CG.DamageType.PHYSICAL, 0.0, wind_up, recover, 0.0, 0, cooldown_ticks)
	a.targets_self = true
	a.applies_status_enabled = true
	a.applies_status = CG.Status.TAUNTING
	a.status_duration_ticks = duration_ticks
	a.taunt_radius = taunt_radius
	return a

## An action that spawns a unit as well as doing whatever else it does.
static func _summons(a: ActionDef, unit_id: StringName) -> ActionDef:
	a.summons_unit_id = unit_id
	return a

static func _projectile(a: ActionDef, speed: float) -> ActionDef:
	a.projectile_speed = speed
	return a

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
