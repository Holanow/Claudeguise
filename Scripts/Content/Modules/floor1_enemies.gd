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
		# 58 melee, tuned against all five real parties with a direct probe
		# (SampleFights doesn't cover single-encounter checks yet). hp
		# landed at 1250 after two lower passes: 620/34 let every party win
		# 20/20 at 63-76% health (too easy to be a boss at all); 950/46
		# still 20/20 everywhere at 38-59%. At 1250/58 the strongest real
		# party at the time (no_abomination -- it carried the old, since-
		# retired 260-range siege_shot) paid a real cost for the first time,
		# 17/20 @23%, while the other four still won comfortably but not for
		# free, 20/20 @33-40%.
		#
		# hp 1250 -> 1000, issue 12: the Siege Master rebuild retired that
		# 260-range exploit, which is what let four of the five real comps
		# above carry a large, safe damage share. Losing it stretched every
		# Warden fight from ~10-30s to 80-100+s (measured -- the axe's own
		# power didn't change, it just had far more time to land), and
		# `no_abomination` went from the strongest real comp to a 0/20
		# guaranteed loss. Lowering hp restores roughly the original fight
		# length for the new, lower realistic squad DPS ceiling rather than
		# re-guessing the damage side: `no_siege_master`/`no_geysermancer`/
		# `no_priest` are 19-20/20 again, `no_warrior` 18/20 (was a 7/20
		# coin flip at 1250). `no_abomination` stays 0/20 at every hp value
		# tried (1250, 1050, 1000) -- it has no tank at all once the Siege
		# Master is not one, which is a roster gap no boss-hp number closes.
		# Disclosed in `Tests/test_content_encounter.gd` rather than chased
		# further; see that file's header for the finding reported to rook.
		_enemy(&"the_warden", "The Warden", 1000, 0, CG.ResourceKind.ENERGY, 1.4, 22.0, {CG.DamageType.PHYSICAL: 58}, 0.05, [&"warden_axe", &"warden_chain_toss"], ["Melee", "Ranged", "Boss"], 0.0),
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
