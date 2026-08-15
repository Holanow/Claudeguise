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
##
## **Issue 129: no class carries a basic attack any more.** The player's own
## instruction -- "a unit's basic attack should be determined by its main hand
## weapon rather than its class". `warrior_strike`, `priest_bolt`,
## `geyser_spout`, `siege_master_shot` and `abomination_claw` were each added
## to give a class something free to fall back on (issues 62 and 79); each is
## now granted by the weapon that class starts with, in `core_items.gd`. The
## actions themselves are unchanged and still live in `core_actions.gd`.
##
## Two consequences worth knowing before editing this file.
##
## 1. **The old "put the free action first" rule is gone, and it had to go.**
##    Every comment below used to explain that `DefaultBehavior` falls back to
##    the *first* non-heal entry in this list, so a class's free attack had to
##    sit at position zero. With the attack arriving from an item that rule
##    could not survive: `Registry.actions_for_pawn` appends equipment grants
##    after class actions, so first-in-list would have made a Warrior "attack"
##    with Guard -- a zero-power self-buff -- and stand still once out of Rage.
##    `DefaultBehavior` now picks the **cheapest action that can actually
##    damage**, which is the weapon's free attack for every armed pawn and does
##    not depend on where anything sits in a list. Order here is now
##    presentation only.
##
## 2. **Nothing here needs a plan or a WIS raise.** A basic attack has never had
##    a preset plan -- it has always arrived through the default behaviour -- so
##    moving it onto a weapon costs no plan blocks and issue 122's budget
##    problem is untouched by this change.

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
			# Issue 160: WIS 8->10, and it is the same move a third time for the
			# same ability the first one was for. `warrior_block` has fired
			# ZERO times since issue 99 moved it onto `plate_mail`: swift
			# measured 40 seeds x 7 encounters, 0 SHIELDING ticks and 0
			# BLOCKED against 9,000+ enemy shots. Three layers had to be
			# wrong at once and each was defensible alone -- the action left
			# `starting_actions` (99), no starter wears armour so nothing
			# grants it, and `warrior_block_default` was deleted in the same
			# issue and nothing replaced it. `DefaultBehavior` cannot reach
			# it either: it is a zero-power self-buff, so `_attack_candidates`
			# excludes it and `_first_heal` never sees it. A preset plan is
			# the only path from the game to this ability, and four plans at
			# 2 blocks each sat exactly at the WIS-8 budget.
			#
			# **WIS still has no combat-stat side effect and I checked rather
			# than repeating it: `Balance.plan_block_budget` is the ONLY
			# reader of `CG.Attribute.WIS` in `Scripts/`** -- everything else
			# that names it is a label in `EquipPanel`, `InspectPanel` or the
			# Glossary. So this changes no damage, health, cost, cooldown or
			# range. It is capacity, not power, which is what made the same
			# raise legal at 4->6 and 6->8.
			{CG.Attribute.STR: 9, CG.Attribute.DEX: 2, CG.Attribute.AGI: 5, CG.Attribute.CON: 14, CG.Attribute.INT: 1, CG.Attribute.ATN: 1, CG.Attribute.WIS: 10},
			# Issue 99: warrior_block left this list for `plate_mail`, where
			# README's own armor table always had it, and warrior_second_wind
			# took its place.
			#
			# Issue 129: warrior_strike leaves too, onto the Sword. What is left
			# is what the Warrior knows rather than what it is holding: a guard,
			# a finisher, a shout and a second wind. Every one of them costs
			# Rage or does no damage, so an *unarmed* Warrior has no free attack
			# at all -- see PawnFactory, which is why a Warrior is never
			# unarmed, and the file header for why that is the shipped answer.
			#
			# WIS stays at 8: four plans at two blocks each, unchanged.
			[&"warrior_guard", &"warrior_execute", &"warrior_taunt", &"warrior_second_wind"]
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
			# Issue 129: priest_bolt leaves this list for the Staff. Smite is
			# the Priest's own ranged spell and stays; the free bolt was only
			# ever here because something had to be affordable when Mana ran
			# out, and that job now belongs to whatever is in the pawn's hand.
			#
			# priest_haste and priest_ward are ally-targeted buffs with no
			# damage of their own, so `DefaultBehavior` cannot pick either as
			# an attack -- structurally, not by ordering: an attack candidate
			# must have `power_scale > 0.0`. They fire only through their own
			# preset plans in PresetPlans.gd.
			[&"priest_heal", &"priest_smite", &"priest_haste", &"priest_ward"]
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
			# Issue 129: geyser_spout leaves this list for the Orb. It was
			# added in issue 79 so a Geysermancer out of Mana had something
			# affordable to fall back to; the Orb is what supplies that now.
				# Issue 87: geyser_cleanse appended last. It is ally-targeted and
				# `DefaultBehavior` must never reach for it -- and cannot,
				# structurally rather than by ordering: `heals` is set, so
				# `_attack_candidates`/`_choose_attack_action` skip it, and
				# `_first_heal` now requires `power_scale > 0.0`, which this
				# action does not have. Its only path into a fight is
				# `geyser_scour_afflicted` in PresetPlans.gd. Appended anyway
				# rather than left out of the list, because `starting_actions` is
				# what the class card shows a player and what
				# `Tests/test_integration_reach.gd` walks; an action a class owns
				# and does not list is invisible to both.
				[&"geyser_blast", &"geyser_scald", &"geyser_cleanse"]
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
			# Issue 129: siege_master_shot leaves this list for the Bow. Note
			# what is left: `spotter_mark` does deal damage (power_scale 1.0),
			# so an unarmed Siege Master is not inert -- it marks, at 15 Mana a
			# time, and its engines still fire. It is simply much worse, which
			# is the point of holding a weapon.
			[&"spotter_mark", &"build_siege_engine"]
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
			# Issue 206: WIS 4 -> 6, for a third plan and nothing else. Pure
			# capacity -- WIS has no combat-stat effect per README, it only
			# governs plan length, the same reasoning as the Warrior's 6->8
			# and the Priest's 5->8. The third plan is
			# `abomination_claw_when_poor`, which is what makes the Sickle's
			# granted Claw reachable at all; see PresetPlans.gd.
			# Issue 219: WIS 6 -> 8, for `abomination_immolate_dump` and nothing
			# else. Pure capacity again -- WIS's only reader in `Scripts/` is
			# `Balance.plan_block_budget`, so this buys two plan blocks and
			# moves no combat number. Same reasoning and same size as the
			# Warrior's 6 -> 8 in #160 and the Priest's 5 -> 8 in #66.
			{CG.Attribute.STR: 5, CG.Attribute.DEX: 1, CG.Attribute.AGI: 8, CG.Attribute.CON: 12, CG.Attribute.INT: 12, CG.Attribute.ATN: 3, CG.Attribute.WIS: 8},
			# Issue 129: abomination_claw leaves this list for the Sickle. Rage
			# only fills from a landed hit and both actions left here cost
			# Rage, so this is the class the weapon matters most to: an unarmed
			# Abomination lands nothing, therefore generates nothing, therefore
			# lands nothing. It starts with a Sickle for exactly that reason.
			# Issue 219: `abomination_immolate` joins the list. It is NOT placed
			# first: `DefaultBehavior` falls back to the first affordable entry,
			# and a fallback that lights a channel is a pawn holding an aura for
			# a reason written in no plan, which is the one thing CLAUDE.md's
			# pawn-behaviour principle forbids. Held only by
			# `abomination_immolate_dump`, which the player can read and edit.
			[&"abomination_hook", &"abomination_grapple", &"abomination_immolate"]
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
