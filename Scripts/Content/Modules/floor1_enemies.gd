extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")

## Floor 1's bestiary: monsters, not mirrors of the five pawn classes.
## `EnemyDef` skips the attribute system on purpose, so nothing here is bound
## to look like a pawn's stat spread. See Registry.gd for the module
## contract. OWNER: teal.
##
## Issue 12: any two of these differ by 2x or more on at least one of
## hp/speed/damage. Goblin vs Ghoul: hp 35 vs 200 (5.7x), speed 4.0 vs 1.6
## (2.5x), damage 9 vs 20 (2.2x) — not a borderline case on any axis.

static func classes() -> Array[ClassDef]:
	return []

static func actions() -> Array[ActionDef]:
	return []

static func enemies() -> Array[EnemyDef]:
	return [
		# Weak, fast, numerous. Meant to show up in groups; one alone is not a threat.
		_enemy(&"goblin", "Goblin", 35, 0, CG.ResourceKind.ENERGY, 4.0, 11.0, {CG.DamageType.PHYSICAL: 9}, 0.0, [&"goblin_stab"], ["Melee", "Weak"]),
		_enemy(&"goblin_archer", "Goblin Archer", 28, 0, CG.ResourceKind.ENERGY, 3.2, 11.0, {CG.DamageType.PHYSICAL: 8}, 0.0, [&"goblin_arrow"], ["Ranged", "Weak"]),
		# Slow and hard to kill, hits hard when it connects. A wall, not a swarm.
		_enemy(&"ghoul", "Ghoul", 200, 0, CG.ResourceKind.ENERGY, 1.6, 16.0, {CG.DamageType.PHYSICAL: 20}, 0.1, [&"ghoul_maul"], ["Melee", "Undead", "Tough"]),
		# Ranged caster, unchanged from the original roster's role.
		_enemy(&"cultist", "Cultist", 50, 0, CG.ResourceKind.ENERGY, 3.0, 12.0, {CG.DamageType.PROFANE: 13}, 0.0, [&"cultist_bolt"], ["Ranged", "Profane"]),
	]

static func encounters() -> Array[Encounter]:
	return []

static func _enemy(id: StringName, display_name: String, hp_max: int, resource_max: int, resource_kind: CG.ResourceKind, move_speed: float, radius: float, attack_power: Dictionary, damage_reduction: float, actions: Array[StringName], display_tags: Array[String]) -> EnemyDef:
	var e := EnemyDef.new()
	e.id = id
	e.display_name = display_name
	e.hp_max = hp_max
	e.resource_max = resource_max
	e.resource_kind = resource_kind
	e.move_speed = move_speed
	e.radius = radius
	e.attack_power = attack_power
	e.damage_reduction = damage_reduction
	e.actions = actions
	e.display_tags = display_tags
	return e
