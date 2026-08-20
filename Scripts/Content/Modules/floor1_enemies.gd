extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")

## Floor 1's bestiary: monsters, not mirrors of the five pawn classes.
## `EnemyDef` skips the attribute system on purpose, so nothing here is bound
## to look like a pawn's stat spread. See Registry.gd for the module

static func classes() -> Array[ClassDef]:
	return []

## Ranged projectile speed. Duplicated from `core_actions.gd` rather than
## reached into: that file's copy is a `const` on another session's module and
## reading a neighbour's private constant is how two numbers start disagreeing
## silently. If issue 93's speed moves again, this moves with it, and the
## reason it is worth having twice is that a mark with no travel time cannot be
## shielded, dodged or seen coming.
const RANGED_PROJECTILE_SPEED := 32.5

## **Issue #121's enemy actions live here, not in `core_actions.gd`, and I was
## wrong about that for two days.**
static func actions() -> Array[ActionDef]:
	return [
		## **The first STUN source in the game**, and it only became worth
		## authoring on 2026-08-14. STUN existed and worked -- a stunned unit
		## is skipped in `_decide_phase` -- but it could not interrupt a
		_action_taunt(&"brute_roar", "Roar", "Forces every enemy within 200 units to attack the Brute for 8 seconds. It cannot roar again for another 16 seconds.", 8, 9, 200.0, 120, 240),
		_action_status(&"brute_slam", "Slam", "A heavy melee blow at up to 50 units that stuns for 0.5 seconds, cancelling whatever the target was casting.", CG.DamageType.PHYSICAL, 50.0, 16, 18, 2.0, 0, CG.Status.STUN, 8),

		## The Stalker's whole arsenal. MARKED for 6 seconds at 220 units,
		## with a projectile so it is a thing in flight the player can watch
		## rather than a status that appears from nowhere.
		_projectile(_action_status_cd(&"stalker_mark", "Mark", "Marks a target within 220 units for 6 seconds, stripping its natural armour.", CG.DamageType.PHYSICAL, 220.0, 4, 5, 1.0, 0, CG.Status.MARKED, 90, 60, true), RANGED_PROJECTILE_SPEED),

		## **The Stalker's second action exists because the cooldown above
		## needs it to, and I found that by running it rather than by reading
		## it.** `DefaultBehavior.decide` builds its candidate list from
		_projectile(_action(&"stalker_dart", "Dart", "A light ranged dart at up to 200 units.", CG.DamageType.PHYSICAL, 200.0, 6, 8, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),

		## **Issue #130's BLEED source, and the fastest action in the game.**
		## 3 ticks of wind-up and 4 of recovery is a bite every 7 ticks, under
		## half the Goblin's 12. The player asked for *"something small that
		_action_status(&"rat_bite", "Bite", "A fast melee bite at up to 40 units that adds a stack of Bleed.", CG.DamageType.PHYSICAL, 40.0, 3, 4, 1.0, 0, CG.Status.BLEED, 45),

		## **Floor 1's miniboss, and README wrote its whole design in one line:**
		## *"Big collection of rats joined at the tail. Ranged attacker, all
		## attacks leave behind rats which are close range melee attackers."*
		_summons(_action(&"rat_king_lash", "Tail Lash", "A ranged strike at up to 200 units that leaves a rat behind.", CG.DamageType.PHYSICAL, 200.0, 20, 22, 1.0, 0, 0, true), &"rat"),
	]

static func enemies() -> Array[EnemyDef]:
	return [
		# Weak, fast, numerous. Meant to show up in groups; one alone is not a
		# threat. A pack that swarms whoever is already bleeding is the whole
		# point of "weak and numerous" being a threat at all -- high focus_bias.
		_enemy(&"goblin", "Goblin", 35, 0, CG.ResourceKind.ENERGY, 4.0, 11.0, {CG.DamageType.PHYSICAL: 9}, 0.0, [&"goblin_stab"], ["Melee", "Weak"], 0.7),
		_enemy(&"goblin_archer", "Goblin Archer", 28, 0, CG.ResourceKind.ENERGY, 3.2, 11.0, {CG.DamageType.PHYSICAL: 8}, 0.0, [&"goblin_arrow"], ["Ranged", "Weak"], 0.6),
		# Slow and hard to kill, hits hard when it connects. A wall, not a
		# swarm -- it walks at whatever is closest and does not care what its
		# allies are doing, so a low focus_bias.
		_enemy(&"ghoul", "Ghoul", 200, 0, CG.ResourceKind.ENERGY, 1.6, 16.0, {CG.DamageType.PHYSICAL: 20}, 0.1, [&"ghoul_maul"], ["Melee", "Undead", "Tough"], 0.1),
		# Ranged caster, unchanged role. Moderate bias: happy to finish a
		# weakened target but not a pure pile-on. Base damage 13->11 (issue 23
		# re-tune): its bolt now also applies POISON, and the two together were
		# pushing the balanced reference party below its win-rate floor.
		_enemy(&"cultist", "Cultist", 50, 0, CG.ResourceKind.ENERGY, 3.0, 12.0, {CG.DamageType.PROFANE: 11}, 0.0, [&"cultist_bolt"], ["Ranged", "Profane"], 0.4),
		# Issue 44: floor 1's boss. High hp and a slow move_speed per README's
		# own "big, slow, scary" -- this is one enemy a full party has to
		# out-fight, not a swarm. warden_axe and warden_chain_toss give it a
		_enemy(&"the_warden", "The Warden", 1000, 0, CG.ResourceKind.ENERGY, 1.4, 22.0, {CG.DamageType.PHYSICAL: 58}, 0.05, [&"warden_axe", &"warden_chain_toss"], ["Melee", "Ranged", "Boss"], 0.0),

		## **Issue #121, the player's "big heavy guy that stuns units and taunts".
		## It now does both, and #150 is what changed.**
		_enemy(&"brute", "Brute", 320, 0, CG.ResourceKind.ENERGY, 1.8, 18.0, {CG.DamageType.PHYSICAL: 24}, 0.15, [&"brute_slam", &"brute_roar"], ["Melee", "Tough", "Stun", "Taunt"], 0.0),

		## **Issue #121's anti-support specialist. Deliberately fragile at 30
		## hp, and my own comment here was wrong when I wrote it** -- it said
		## "the squishiest thing in the game, under the Goblin Archer's 28 by
		_enemy(&"stalker", "Stalker", 30, 0, CG.ResourceKind.ENERGY, 3.8, 10.0, {CG.DamageType.PHYSICAL: 5}, 0.0, [&"stalker_mark", &"stalker_dart"], ["Ranged", "Weak", "Support"], 0.5),

		## **Issue #130's BLEED source. The player's words are "something small
		## that hits fast", and every number here is that sentence and nothing
		## else.**
		_enemy(&"rat", "Rat", 20, 0, CG.ResourceKind.ENERGY, 5.0, 8.0, {CG.DamageType.PHYSICAL: 3}, 0.0, [&"rat_bite"], ["Melee", "Weak", "Bleed"], 0.8),

		## **Floor 1's miniboss. README pairs it with The Warden, and it is the
		## opposite kind of fight in every way I could make it.**
		_enemy(&"rat_king", "The Rat King", 420, 0, CG.ResourceKind.ENERGY, 1.2, 24.0, {CG.DamageType.PHYSICAL: 21}, 0.0, [&"rat_king_lash"], ["Ranged", "Miniboss", "Summoner"], 0.0),
	]

static func encounters() -> Array[Encounter]:
	return []

static func items() -> Array[EquipmentDef]:
	return []

## The two action helpers this module needs, and they are copies of
## `core_actions.gd`'s rather than calls into it. Those are `static func _`
## names -- private by this project's own convention -- on a module another
## session owns, and a cross-module call to one would make every signature
## change in that file a break in this one. Two small constructors are cheaper
## than that coupling, and `Registry` composes modules precisely so a module
## can be read on its own.
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
## `core_actions.gd`'s `_action_summon` is not this: it hardcodes
## `power_scale` 0.0 and a self-target, because every summon before this one
## was a dedicated build action. The Rat King's lash is an attack that happens
## to shed a rat, which is what "all attacks leave behind rats" means.
static func _summons(a: ActionDef, unit_id: StringName) -> ActionDef:
	a.summons_unit_id = unit_id
	return a

static func _projectile(a: ActionDef, speed: float) -> ActionDef:
	a.projectile_speed = speed
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
