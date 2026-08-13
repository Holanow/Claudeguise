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
		# real answer to both playstyles the earlier placeholder favoured
		# unevenly: axe for whoever closes, chain for whoever does not.
		#
		# 1250 hp / 58 melee, tuned against all five real parties with a
		# direct probe (SampleFights doesn't cover single-encounter checks
		# yet). Landed here after two lower passes: 620/34 let every party win
		# 20/20 at 63-76% health (too easy to be a boss at all); 950/46 still
		# 20/20 everywhere at 38-59%. At 1250/58 the strongest real party
		# (no_abomination) pays a real cost for the first time, 17/20 @23%,
		# while the other four still win comfortably but not for free,
		# 20/20 @33-40%. No comp trivialises it and none is uniquely
		# punished -- the inversion the placeholder had (19/20 @86% for one
		# comp, 1/20 for another) is gone.
		_enemy(&"the_warden", "The Warden", 1250, 0, CG.ResourceKind.ENERGY, 1.4, 22.0, {CG.DamageType.PHYSICAL: 58}, 0.05, [&"warden_axe", &"warden_chain_toss"], ["Melee", "Ranged", "Boss"], 0.0),
	]

static func encounters() -> Array[Encounter]:
	return []

static func items() -> Array[EquipmentDef]:
	return []

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
