extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")

## Every ActionDef in the slice: the five classes' actions and the enemies'.
## Kept in one module rather than split per class because Registry only cares
## about ids, and a reviewer checking "what can this class actually do" reads
## faster from one file than five. See Registry.gd for the module contract.
## OWNER: teal.

static func classes() -> Array[ClassDef]:
	return []

static func actions() -> Array[ActionDef]:
	return [
		_action(&"warrior_strike", "Strike", CG.DamageType.PHYSICAL, 40.0, 6, 8, 1.0, 0, 0),
		_action_status(&"warrior_guard", "Guard", CG.DamageType.EARTH, 0.0, 4, 10, 0.0, 20, CG.Status.BLOCK, 90),
		_action(&"warrior_execute", "Execute", CG.DamageType.PHYSICAL, 40.0, 8, 10, 2.0, 60, 40),

		_action_heal(&"priest_heal", "Heal", CG.DamageType.DIVINE, 220.0, 8, 10, 1.4, 25),
		_action(&"priest_smite", "Smite", CG.DamageType.DIVINE, 220.0, 10, 10, 0.9, 15, 0),

		_action_splash(&"geyser_blast", "Geyser Blast", CG.DamageType.WATER, 200.0, 50.0, 12, 12, 0.8, 20),
		_action(&"geyser_scald", "Scald", CG.DamageType.FIRE, 200.0, 8, 8, 1.0, 15, 0),

		_action(&"siege_shot", "Siege Shot", CG.DamageType.PHYSICAL, 260.0, 10, 10, 1.1, 10, 0),
		_action_splash_cd(&"siege_barrage", "Barrage", CG.DamageType.RAW, 240.0, 40.0, 14, 14, 0.9, 30, 30),

		_action_status(&"abomination_claw", "Claw", CG.DamageType.PROFANE, 45.0, 7, 9, 1.0, 0, CG.Status.POISON, 90),
		_action_splash(&"abomination_immolate", "Immolate", CG.DamageType.FIRE, 45.0, 60.0, 10, 12, 1.2, 40),

		_action(&"grunt_smash", "Smash", CG.DamageType.PHYSICAL, 40.0, 10, 10, 1.0, 0, 0),
		_action(&"archer_shot", "Arrow", CG.DamageType.PHYSICAL, 220.0, 12, 10, 0.8, 0, 0),
		_action(&"cultist_bolt", "Dark Bolt", CG.DamageType.PROFANE, 200.0, 10, 10, 0.7, 0, 0),
	]

static func enemies() -> Array[EnemyDef]:
	return []

static func encounters() -> Array[Encounter]:
	return []

static func _action(id: StringName, display_name: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.display_name = display_name
	a.damage_type = damage_type
	a.range_units = range_units
	a.wind_up_ticks = wind_up
	a.recover_ticks = recover
	a.power_scale = power_scale
	a.resource_cost = resource_cost
	a.cooldown_ticks = cooldown_ticks
	return a

static func _action_heal(id: StringName, display_name: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int) -> ActionDef:
	var a := _action(id, display_name, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0)
	a.heals = true
	return a

static func _action_splash(id: StringName, display_name: String, damage_type: CG.DamageType, range_units: float, splash_radius: float, wind_up: int, recover: int, power_scale: float, resource_cost: int) -> ActionDef:
	var a := _action(id, display_name, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0)
	a.splash_radius = splash_radius
	return a

static func _action_splash_cd(id: StringName, display_name: String, damage_type: CG.DamageType, range_units: float, splash_radius: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int) -> ActionDef:
	var a := _action_splash(id, display_name, damage_type, range_units, splash_radius, wind_up, recover, power_scale, resource_cost)
	a.cooldown_ticks = cooldown_ticks
	return a

static func _action_status(id: StringName, display_name: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, status: CG.Status, duration_ticks: int) -> ActionDef:
	var a := _action(id, display_name, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0)
	a.applies_status_enabled = true
	a.applies_status = status
	a.status_duration_ticks = duration_ticks
	return a
