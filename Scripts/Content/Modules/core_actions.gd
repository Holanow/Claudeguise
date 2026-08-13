extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")

## Every ActionDef in the slice: the five classes' actions and the enemies'.
## Kept in one module rather than split per class because Registry only cares
## about ids, and a reviewer checking "what can this class actually do" reads
## faster from one file than five. See Registry.gd for the module contract.
## OWNER: teal.

static func classes() -> Array[ClassDef]:
	return []

## Issue 28b: which actions declare `requires_line_of_sight`. Every ranged
## attack, whichever side fires it -- a wall denying a shot is the point of
## the field, and letting an enemy's own arrows and bolts ignore it would
## make terrain a one-sided lever. `priest_heal` is the one deliberate
## exception: it is support reaching an ally rather than a shot at an enemy,
## and denying it would turn "stand behind cover" into "your healer cannot
## reach you," which is a worse game than the one wall-hiding was meant to
## create. Every melee action stays false -- adjacency already means nothing
## stands between the two.
static func actions() -> Array[ActionDef]:
	return [
		_action(&"warrior_strike", "Strike", "A reliable melee swing that costs nothing. The Warrior's bread and butter.", CG.DamageType.PHYSICAL, 40.0, 6, 8, 1.0, 0, 0),
		_action_status(&"warrior_guard", "Guard", "Raises a block, cutting incoming damage for a while. Spends Rage to buy safety instead of dealing it.", CG.DamageType.EARTH, 0.0, 4, 10, 0.0, 20, CG.Status.BLOCK, 90),
		_action(&"warrior_execute", "Execute", "A heavy finishing blow that spends most of the Warrior's Rage in one swing. Hits far harder than a Strike.", CG.DamageType.PHYSICAL, 40.0, 8, 10, 2.0, 60, 40),

		_action_heal(&"priest_heal", "Heal", "Restores an ally's health from range. The Priest's whole job in one action.", CG.DamageType.DIVINE, 220.0, 8, 10, 1.4, 25),
		_action(&"priest_smite", "Smite", "A ranged bolt of divine light. What the Priest does when nobody needs healing.", CG.DamageType.DIVINE, 220.0, 10, 10, 0.9, 15, 0, true),

		_action_splash(&"geyser_blast", "Geyser Blast", "A splash of scalding water that can catch several enemies standing close together.", CG.DamageType.WATER, 200.0, 50.0, 12, 12, 0.8, 20, true),
		_action(&"geyser_scald", "Scald", "A focused burst of fire at a single target, cheaper and faster than a Geyser Blast.", CG.DamageType.FIRE, 200.0, 8, 8, 1.0, 15, 0, true),

		_action(&"siege_shot", "Siege Shot", "A long-range physical shot. The Siege Master's most reliable attack.", CG.DamageType.PHYSICAL, 260.0, 10, 10, 1.1, 10, 0, true),
		_action_splash_cd(&"siege_barrage", "Barrage", "A heavy splash attack on a cooldown, meant for enemies standing in a cluster.", CG.DamageType.RAW, 240.0, 40.0, 14, 14, 0.9, 30, 30, true),

		_action_status(&"abomination_claw", "Claw", "A poisoned melee strike that keeps hurting the target after it lands.", CG.DamageType.PROFANE, 45.0, 7, 9, 1.0, 0, CG.Status.POISON, 90),
		_action_splash(&"abomination_immolate", "Immolate", "A fiery melee burst that can catch nearby enemies, spending most of the Abomination's Rage.", CG.DamageType.FIRE, 45.0, 60.0, 10, 12, 1.2, 40),

		_action(&"goblin_stab", "Stab", "A weak melee jab. Barely a threat alone; dangerous in a pack.", CG.DamageType.PHYSICAL, 40.0, 6, 6, 1.0, 0, 0),
		_action(&"goblin_arrow", "Arrow", "A weak ranged shot. Like the Stab, meant to add up in numbers rather than hit hard alone.", CG.DamageType.PHYSICAL, 200.0, 8, 8, 1.0, 0, 0, true),
		_action(&"ghoul_maul", "Maul", "A slow, heavy melee blow that lands far harder than its speed suggests.", CG.DamageType.PHYSICAL, 45.0, 14, 14, 1.0, 0, 0),
		# Issue 23: the bestiary's status user. Profane -> POISON per README.md.
		_action_status(&"cultist_bolt", "Dark Bolt", "A ranged bolt of dark energy that leaves the target poisoned.", CG.DamageType.PROFANE, 200.0, 10, 10, 0.7, 0, CG.Status.POISON, 90, true),

		# Issue 44: The Warden, floor 1's boss (README's own name and flavour
		# -- "big, slow, scary, wields an executioner's axe that can do a ton
		# of damage at close range"). Two actions rather than one, and the
		# second is the fix for issue 37's diagnosed mechanism: every enemy
		# in the room stopped at 200 units while siege_shot reached 260, so a
		# ranged party could decline the fight entirely and pay nothing.
		# warden_chain_toss reaches 270 -- past every player action in the
		# game -- so standing at range is no longer free; it hits softer than
		# the axe on purpose, since the point is denying safety, not
		# out-damaging melee.
		_action(&"warden_axe", "Executioner's Axe", "A single devastating swing. Slow to wind up, and worth staying clear of.", CG.DamageType.PHYSICAL, 55.0, 20, 22, 2.4, 0, 0),
		_action(&"warden_chain_toss", "Chain Toss", "A weighted chain, thrown further than anything else in the room reaches back.", CG.DamageType.PHYSICAL, 270.0, 16, 18, 1.0, 0, 0, true),

		## Issue 12 retired dungeon_grunt/dungeon_archer/dungeon_cultist from
		## the bestiary, but these two actions are still referenced by name in
		## wren's Tests/test_combat_sim.gd (kiting regression checks). Kept
		## rather than deleted: additive is safe, and it is wren's test to
		## repoint, not mine to break out from under them. No EnemyDef spawns
		## with these ids any more, so no player ever reads these descriptions.
		_action(&"grunt_smash", "Smash", "Retired from the bestiary; kept only so an older test fixture referencing it by name still resolves.", CG.DamageType.PHYSICAL, 40.0, 10, 10, 1.0, 0, 0),
		_action(&"archer_shot", "Arrow", "Retired from the bestiary; kept only so an older test fixture referencing it by name still resolves.", CG.DamageType.PHYSICAL, 220.0, 12, 10, 0.8, 0, 0),
	]

static func enemies() -> Array[EnemyDef]:
	return []

static func encounters() -> Array[Encounter]:
	return []

static func items() -> Array[EquipmentDef]:
	return []

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

static func _action_heal(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0)
	a.heals = true
	return a

static func _action_splash(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, splash_radius: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, requires_los: bool = false) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0, requires_los)
	a.splash_radius = splash_radius
	return a

static func _action_splash_cd(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, splash_radius: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int, requires_los: bool = false) -> ActionDef:
	var a := _action_splash(id, display_name, description, damage_type, range_units, splash_radius, wind_up, recover, power_scale, resource_cost, requires_los)
	a.cooldown_ticks = cooldown_ticks
	return a

static func _action_status(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, status: CG.Status, duration_ticks: int, requires_los: bool = false) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0, requires_los)
	a.applies_status_enabled = true
	a.applies_status = status
	a.status_duration_ticks = duration_ticks
	return a
