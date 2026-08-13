extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")

## Enemy types for the one room in this slice. See Registry.gd for the module
## contract. OWNER: teal.

static func classes() -> Array[ClassDef]:
	return []

static func actions() -> Array[ActionDef]:
	return []

static func enemies() -> Array[EnemyDef]:
	return [
		_enemy(&"dungeon_grunt", "Grunt", 90, 0, CG.ResourceKind.ENERGY, 3.5, 14.0, {CG.DamageType.PHYSICAL: 14}, 0.05, [&"grunt_smash"], ["Melee", "Brute"]),
		_enemy(&"dungeon_archer", "Archer", 55, 0, CG.ResourceKind.ENERGY, 3.0, 12.0, {CG.DamageType.PHYSICAL: 10}, 0.0, [&"archer_shot"], ["Ranged"]),
		_enemy(&"dungeon_cultist", "Cultist", 50, 0, CG.ResourceKind.ENERGY, 3.0, 12.0, {CG.DamageType.PROFANE: 11}, 0.0, [&"cultist_bolt"], ["Ranged", "Profane"]),
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
