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

		# Issue 12: siege_shot and siege_barrage retired along with the range
		# that made the class mandatory (260, past every enemy's own reach --
		# see issue 25/31). The Siege Master is a spotter/engineer now,
		# per the player's own spec, and both of its new actions put
		# something in the room's reach: a marked target is a target the
		# room can still see, and an engine is a unit the room can attack.
		#
		# spotter_mark: a light ranged hit that leaves MARKED for 5s
		# (150 ticks -- long enough to matter across several of the
		# Siege Master's own attacks and an ally's, not so long it never
		# falls off between engagements). 220 range matches the rest of
		# the room's ranged cast (geyser_blast, priest_smite, cultist_bolt)
		# rather than reaching past it. power_scale first tried at 0.5,
		# meant to read as a debuff that also chips damage rather than a
		# real attack -- measured (Tools/FloorRuns.gd) as part of why the
		# class contributed almost no net damage across a fight and every
		# real party carrying it lost every floor room. Raised to 1.0, in
		# line with a normal single-target hit: the debuff is still the
		# point, but the hit landing it should not be a rounding error.
		_action_status(&"spotter_mark", "Spotter's Mark", "Marks a target and lowers its defenses, letting the whole party's next hits land harder.", CG.DamageType.PHYSICAL, 220.0, 10, 10, 1.0, 15, CG.Status.MARKED, 150, true),
		# build_siege_engine: self-targeted (range 0, no line-of-sight
		# needed), deals no damage of its own -- power_scale 0.0, the
		# summon is the whole effect. wind_up 90 ticks (3s) is the "takes a
		# bit" the player asked for, long enough to be a real commitment
		# mid-fight and not just a free extra unit.
		#
		# Cost first tried at 40 of a 50ish-max Mana pool, gated behind a
		# self_resource_at_least: 45 plan condition (PresetPlans.gd) so it
		# fired once near the start of a fight and only rarely again --
		# matching Warrior's Execute/Rage, but this class has no other real
		# damage source while waiting, unlike Warrior's basic swing. Lowered
		# to 20/threshold 25 so a fight long enough to matter (most of them)
		# gets a second or third engine out of the same Mana pool, which is
		# what "having two of these on the field" (see siege_engine_bolt's
		# own comment) actually requires instead of just describing.
		_action_summon(&"build_siege_engine", "Build Siege Engine", "Spends time building a siege engine that then fights at range on its own. Takes a while, and worth doing early.", 90, 20, 20, &"siege_engine"),

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

		# Issue 12: the siege engine's own attack, once built. Ranged and
		# reliable rather than powerful on its own -- the Siege Master's
		# contribution is having two of these on the field, not one hitting
		# hard. 200 range, same band as the room's other ranged casters.
		_action(&"siege_engine_bolt", "Engine Bolt", "A heavy bolt fired by a siege engine.", CG.DamageType.PHYSICAL, 200.0, 12, 12, 1.0, 0, 0, true),

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
	return [
		# Issue 12: the Siege Master's engineer half. `EnemyDef` reused rather
		# than a new summon shape -- it already describes exactly what this
		# is, a non-pawn unit with hp, damage, an action and a move speed,
		# and the only thing that made it read as "enemy" was which team
		# spawned it. Stationary (move_speed 0.0): it is artillery the room
		# has to come to, which is the entire point of putting something in
		# the room's reach that the Siege Master itself no longer is.
		# hp first tried at 80 so "the room can attack it" (criterion 1) was
		# real rather than nominal -- died in a couple of hits from anything
		# that reached it, same as the Siege Master itself. Measured
		# (Tools/_probe, throwaway) against a real fight and found the
		# opposite problem: enemies do not preferentially target a summon at
		# all (`DefaultBehavior._choose_target` is nearest-only for player-
		# side units, focus_bias has no equivalent here), so the engine sat
		# unengaged for most of a fight and died the moment something
		# finally reached it, contributing little either way. Raised to 140
		# so a build that does draw fire survives long enough to matter, not
		# to make it a tank -- it still dies fast to concentrated fire, it
		# just isn't a coin flip against a single stray hit any more.
		_enemy(&"siege_engine", "Siege Engine", 140, 0, CG.ResourceKind.ENERGY, 0.0, 20.0, {CG.DamageType.PHYSICAL: 16}, 0.0, [&"siege_engine_bolt"], ["Ranged", "Construct"], 0.0),
	]

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

## Issue 12: self-targeted (range 0.0, no line-of-sight check), deals no
## damage of its own (power_scale 0.0) -- summons_unit_id is the entire
## effect. `_action` already covers everything else this needs.
static func _action_summon(id: StringName, display_name: String, description: String, wind_up: int, recover: int, resource_cost: int, summons_unit_id: StringName) -> ActionDef:
	var a := _action(id, display_name, description, CG.DamageType.PHYSICAL, 0.0, wind_up, recover, 0.0, resource_cost, 0)
	a.summons_unit_id = summons_unit_id
	return a

static func _enemy(id: StringName, display_name: String, hp_max: int, resource_max: int, resource_kind: CG.ResourceKind, move_speed: float, radius: float, attack_power: Dictionary, damage_reduction: float, actions: Array[StringName], display_tags: Array[String], focus_bias: float = 0.0) -> EnemyDef:
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
	e.focus_bias = focus_bias
	return e
