extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")

## The five README classes: Warrior, Priest, Geysermancer, Siege Master,
## Abomination. Attribute spreads are original tuning, not a transcription of
## README.md: the table there ships with the attribute columns blank on
## purpose. See Registry.gd for the module contract. OWNER: teal.

static func classes() -> Array[ClassDef]:
	return [
		_class(
			&"warrior", "Warrior",
			CG.Method.MARTIAL, CG.Style.MELEE, CG.Role.TANK, CG.Role.DPS,
			[CG.DamageType.PHYSICAL, CG.DamageType.EARTH],
			CG.ResourceKind.RAGE,
			# Issue 30, second pass: CON 9->14. rook's own framing after
			# measuring the first pass -- "a taunting Warrior that dies
			# inside its own taunt window is a worse tank than one that
			# never taunted" -- and that is exactly what happened: the
			# Warrior drew The Warden's full attention and died at tick 203
			# of its own 240-tick taunt, every time, regardless of CON.
			# Swept CON 9/14/20/26/35 directly against `Tools/FloorRuns.gd`
			# rather than guessing at one number: 14 (with warrior_guard's
			# threshold below) already took no_siege_master/no_geysermancer/
			# no_priest to a clean 20/20 each; 20, 26 and 35 bought no
			# further wins anywhere and only cosmetically raised
			# no_abomination's own boss-entry health (67%->79%) without ever
			# converting a single loss to a win. Stopped at 14 rather than
			# chasing diminishing returns into an implausible stat -- see
			# PresetPlans.gd's own comment on warrior_guard for why raw CON
			# alone was never going to fix the one comp it didn't.
			# Issue 52: WIS 4->6. warrior_block needed a third preset plan to
			# actually fire in real play -- SHIELDING existed in the
			# simulation since PR #33 with nothing to intercept until shots
			# travel, and there is no plan editor yet, so a preset plan is
			# the only path from the game to the ability at all, the same
			# failure mode issue 52 was filed over. Two plans at 2 blocks
			# each already sat exactly at the old WIS-4 budget
			# (Balance.plan_block_budget == WIS), so a third plan needed the
			# budget raised, not just the plan added. WIS has no combat-stat
			# side effect per README (it only governs plan length), so this
			# is a pure capacity increase, not a power change.
			# Issue 79: WIS 6->8. warrior_execute has had no preset plan since
			# issue 30 deleted `warrior_execute_when_raging`, and there is
			# still no plan editor, so a preset plan is the only path from
			# the game to this ability at all -- the exact reasoning issue
			# 52's own WIS 4->6 note records for warrior_block. Three plans
			# at 2 blocks each already sat exactly at the WIS-6 budget
			# (`Balance.plan_block_budget` == WIS), so a fourth needed the
			# budget raised, not just the plan added. WIS has no combat-stat
			# side effect per README (it only governs plan length), so this
			# is a pure capacity increase, not a power change -- same shape
			# as the Priest's own 5->8 for a fourth plan.
			#
			# ATN and INT deliberately left at 1. Raising either would also
			# have made Execute affordable (the Rage pool is
			# `30 + ATN*8 + INT*2`), but by inflating what every Rage cost
			# means at once; the cost came down instead. See
			# warrior_execute's own comment in core_actions.gd.
			{CG.Attribute.STR: 9, CG.Attribute.DEX: 2, CG.Attribute.AGI: 5, CG.Attribute.CON: 14, CG.Attribute.INT: 1, CG.Attribute.ATN: 1, CG.Attribute.WIS: 8},
			# Issue 30: warrior_taunt appended at the end, not the front --
			# DefaultBehavior._first_non_heal falls back to the FIRST
			# non-heal action in this list whenever no plan fires (there is
			# no plan for warrior_strike itself; it has always relied on
			# that fallback). warrior_taunt and warrior_block (issue 52) are
			# both self-targeted and would be a no-op as a fallback "attack
			# an enemy" action, so warrior_strike must stay first regardless
			# of where either plan sits in PresetPlans.
			[&"warrior_strike", &"warrior_guard", &"warrior_execute", &"warrior_taunt", &"warrior_block"]
		),
		_class(
			&"priest", "Priest",
			CG.Method.MAGICAL, CG.Style.RANGED, CG.Role.HEALER, CG.Role.SUPPORT,
			[CG.DamageType.DIVINE, CG.DamageType.AIR],
			CG.ResourceKind.MANA,
			# WIS 5->8: two new preset plans (priest_haste, priest_ward, the
			# player's own "one for speed, one for resistance" direction) at
			# 2 blocks each, on top of the existing 2 plans' own 4 -- 8
			# blocks total, and Balance.plan_block_budget == WIS. Same "pure
			# capacity increase, not a power change" reasoning as the
			# Warrior's own WIS 4->6 for a third plan (issue 52): WIS has no
			# combat-stat side effect per README, it only governs plan length.
			{CG.Attribute.STR: 1, CG.Attribute.DEX: 2, CG.Attribute.AGI: 4, CG.Attribute.CON: 3, CG.Attribute.INT: 8, CG.Attribute.ATN: 7, CG.Attribute.WIS: 8},
			# Issue 62: priest_bolt (no cost) placed before priest_smite --
			# DefaultBehavior._first_non_heal falls back to the first
			# non-heal action in this list whenever no plan fires, and
			# priest_smite_nearest's own plan already falls through to
			# here the moment Mana can't cover Smite. Same reasoning as
			# warrior_strike staying first for the Warrior.
			#
			# priest_haste and priest_ward, appended: both are ally-targeted
			# buffs, never picked by DefaultBehavior's own fallback (Priest
			# has zero melee actions, so `_choose_attack_action` always
			# defers straight to `_first_non_heal`, which stops at
			# `priest_bolt` regardless of where these two sit) -- they only
			# ever fire through their own preset plans in PresetPlans.gd.
			[&"priest_heal", &"priest_bolt", &"priest_smite", &"priest_haste", &"priest_ward"]
		),
		_class(
			&"geysermancer", "Geysermancer",
			CG.Method.MAGICAL, CG.Style.RANGED, CG.Role.DPS, CG.Role.SUPPORT,
			[CG.DamageType.WATER, CG.DamageType.FIRE],
			CG.ResourceKind.MANA,
			# Issue 79: WIS 4->6. Two plans at 2 blocks each sat exactly at
			# the WIS-4 budget, and this class needs a third (see
			# PresetPlans.gd: the Blast/Scald ladder is what makes Scald
			# reachable at all). Same pure-capacity reasoning as the
			# Warrior's 6->8 above and the Priest's 5->8 before it.
			{CG.Attribute.STR: 1, CG.Attribute.DEX: 3, CG.Attribute.AGI: 4, CG.Attribute.CON: 3, CG.Attribute.INT: 8, CG.Attribute.ATN: 7, CG.Attribute.WIS: 6},
			# Issue 79: geyser_spout (no cost) placed first --
			# `DefaultBehavior._first_non_heal` falls back to the first
			# non-heal action in this list whenever no plan fires, and every
			# plan below falls through to here the moment Mana cannot cover
			# it. Before this the fallback was geyser_blast, which costs 20
			# Mana: a Geysermancer out of Mana had nothing affordable to
			# fall back to at all. Same reasoning, and the same fix, as
			# priest_bolt and siege_master_shot in issue 62.
			[&"geyser_spout", &"geyser_blast", &"geyser_scald"]
		),
		## Issue 12: rebuilt as spotter/engineer, per the player's own spec.
		## `Style.SUMMONER` was on the class card while it played as pure
		## artillery (siege_shot at 260 range, past every enemy's own reach
		## -- issue 25/31's diagnosis for why this class was mandatory);
		## `build_siege_engine` is what makes the tag true. Resource kind
		## ENERGY->MANA -- the old fast regen (18%/s) suited firing every
		## tick; MANA's slower 4%/s is what gates `build_siege_engine` from
		## being re-cast every few seconds, the same way Rage gates
		## Warrior's Execute.
		##
		## CON first tried at 2, below even the Priest's 3 -- squishy was
		## the spec, criterion 3. Measured with `Tools/FloorRuns.gd` and it
		## overshot: every real party carrying this class lost every floor
		## room it reached (0/20), because the pawn itself, not the engine,
		## was the room's first and easiest kill and died before
		## contributing much of anything. Restored to 4 (its own pre-rebuild
		## value) -- a point above Priest/Geysermancer's 3, so no longer the
		## single squishiest CON in the game, but still far below Warrior/
		## Abomination's 9-12 and still the squishiest kit-wise: no
		## self-heal, no shield, no reach advantage any more, just enough hp
		## to not be the free first kill for whichever enemy happens to be
		## nearest when it stops to cast.
		_class(
			&"siege_master", "Siege Master",
			CG.Method.MARTIAL, CG.Style.SUMMONER, CG.Role.DPS, CG.Role.ANTI_SUPPORT,
			[CG.DamageType.PHYSICAL, CG.DamageType.RAW],
			CG.ResourceKind.MANA,
			{CG.Attribute.STR: 3, CG.Attribute.DEX: 9, CG.Attribute.AGI: 5, CG.Attribute.CON: 4, CG.Attribute.INT: 2, CG.Attribute.ATN: 2, CG.Attribute.WIS: 4},
			# Issue 62: siege_master_shot (no cost) placed first --
			# DefaultBehavior._first_non_heal falls back to the first action
			# in this list whenever no plan fires, and both spotter_mark_
			# default and siege_master_build_when_ready already fall through
			# to here the moment Mana can't cover them. Before this, the
			# fallback was spotter_mark itself, which also costs Mana -- a
			# Siege Master out of Mana had nothing affordable to fall back
			# to at all.
			[&"siege_master_shot", &"spotter_mark", &"build_siege_engine"]
		),
		## CON 8->10 (issue 24, history only, superseded below). AGI 2->8,
		## CON 10->12, INT 7->12 (issue 37): the leave-one-out ablation showed
		## the party missing this class (no_abomination) as the best in the
		## game, 19/20, and the party missing the Siege Master as the worst,
		## 0/20 -- same three other classes both times. Traced with
		## Tools/WhyNoDamage.gd: this class fired only 5 actions across a
		## whole fight against a Siege Master's 22, mostly spent closing the
		## ~500-unit gap to its own 45-range melee kit at a crawl (AGI 2).
		## AGI raised so it actually reaches the fight; INT raised (this is a
		## MAGICAL class, so INT drives its attack power per Balance.gd) so
		## the actions it does land matter; CON raised alongside so more
		## uptime doesn't just mean dying faster. Landed at this combination
		## after several rounds against all five real parties in
		## Tools/SampleFights.gd: pushing INT alone to 15 fixed the bottom row
		## but inflated the three middle parties past their own coin-flip
		## bands (16-17/20); this split gets three of the five into a genuine
		## 11-13/20 coin flip without any party hitting 20/20, but does not
		## fully clear issue 37's 4-6 target for the Siege-Master-less party
		## (measured 1/20) -- disclosed on the board rather than forced.
		# Issue 52 retired abomination_claw and abomination_immolate,
		# replaced by abomination_hook and abomination_grapple. Issue 62
		# restored claw (the player's own direction) and put it first --
		# see that action's own comment in core_actions.gd for why.
		_class(
			&"abomination", "Abomination",
			CG.Method.MAGICAL, CG.Style.MELEE, CG.Role.ANTI_SUPPORT, CG.Role.TANK,
			[CG.DamageType.PROFANE, CG.DamageType.FIRE],
			CG.ResourceKind.RAGE,
			{CG.Attribute.STR: 5, CG.Attribute.DEX: 1, CG.Attribute.AGI: 8, CG.Attribute.CON: 12, CG.Attribute.INT: 12, CG.Attribute.ATN: 3, CG.Attribute.WIS: 4},
			# Issue 62: abomination_claw restored and placed first -- both
			# hook and grapple cost Rage, and Rage only fills from a landed
			# hit, so a Rage-starved Abomination needs a no-cost fallback the
			# same way Warrior's strike is one. DefaultBehavior._first_non_
			# heal falls back to whichever action sits first here whenever no
			# plan fires; both preset plans below already fall through to
			# here the moment Rage can't cover hook or grapple.
			[&"abomination_claw", &"abomination_hook", &"abomination_grapple"]
		),
	]

static func actions() -> Array[ActionDef]:
	return []

static func enemies() -> Array[EnemyDef]:
	return []

static func encounters() -> Array[Encounter]:
	return []

static func items() -> Array[EquipmentDef]:
	return []

static func _class(id: StringName, display_name: String, method: CG.Method, style: CG.Style, role_primary: CG.Role, role_secondary: CG.Role, damage_types: Array, resource_kind: CG.ResourceKind, base_attributes: Dictionary, starting_actions: Array[StringName]) -> ClassDef:
	var c := ClassDef.new()
	c.id = id
	c.display_name = display_name
	c.method = method
	c.style = style
	c.role_primary = role_primary
	c.role_secondary = role_secondary
	var dts: Array[int] = []
	for d in damage_types:
		dts.append(int(d))
	c.damage_types = dts
	c.resource_kind = resource_kind
	c.base_attributes = base_attributes
	c.starting_actions = starting_actions
	return c
