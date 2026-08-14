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
		_action(&"warrior_strike", "Strike", "A reliable melee swing that costs nothing.", CG.DamageType.PHYSICAL, 40.0, 6, 8, 1.0, 0, 0),
		_action_status(&"warrior_guard", "Guard", "Raises a block that reduces damage taken by 25% for 3 seconds. Costs 20 Rage.", CG.DamageType.EARTH, 0.0, 4, 10, 0.0, 20, CG.Status.BLOCK, 90),
		_action(&"warrior_execute", "Execute", "A heavy melee blow that deals twice the damage of a Strike. Costs 60 Rage.", CG.DamageType.PHYSICAL, 40.0, 8, 10, 2.0, 60, 40),
		# Issue 30/TAUNTING: self-targeted (target_self, same pattern
		# build_siege_engine uses), no damage of its own -- the status is
		# the whole effect. 350 radius covers a real engagement (every
		# enemy action in the bestiary ranges 200-270, so a Warrior that
		# has closed to a normal fighting distance covers the room without
		# this reaching arena-wide from any position -- diagonal is ~1100).
		# duration_ticks 240 (8s) and cooldown_ticks the same: the Warrior
		# can hold the room's attention essentially permanently once
		# established, recasting the instant it lapses, but a fight that
		# opens with the Warrior out of position or dead loses that cover
		# entirely rather than it running on a timer regardless. Costs no
		# Rage on purpose -- a shout should not compete with Execute for
		# the same resource, and it needs to be castable turn one before
		# any Rage has built at all.
		_action_taunt(&"warrior_taunt", "Taunt", "Forces every enemy within 350 units to attack the caster for 8 seconds.", 6, 10, 350.0, 240),
		# Issue 52: the directional block the player asked for and found
		# missing -- SHIELDING existed in the simulation (PR #33) since
		# before shots could travel, and had nothing to intercept until
		# issue 18 landed. Self-targeted, no damage, same shape as
		# warrior_taunt: duration_ticks 150 (5s) and cooldown_ticks the
		# same, so it recasts the instant it lapses rather than running on
		# a fixed timer independent of whether it is still up.
		#
		# Built with `_action_self_buff`, not `_action_status` -- found by
		# tracing a real fight (a throwaway probe, not committed) after this
		# action first shipped through `_action_status`, which hardcodes
		# cooldown_ticks to 0. A self-targeted, zero-cost, zero-cooldown,
		# `always`-conditioned action is *always* affordable, so it won
		# every decide() tick forever: the Warrior cast this once every ~15
		# ticks for the whole fight and never cast warrior_taunt again or
		# fell through to warrior_strike at all, in every real party the
		# gate measured. Costs no Rage, same reasoning as taunt: it should
		# not compete with Execute for the same pool.
		_action_self_buff(&"warrior_block", "Directional Block", "Raises a shield that stops a travelling shot aimed at an ally standing behind it, for 5 seconds.", CG.DamageType.EARTH, 6, 10, CG.Status.SHIELDING, 150),

		_action_heal(&"priest_heal", "Heal", "Restores health to an ally within 220 units.", CG.DamageType.DIVINE, 220.0, 8, 10, 1.4, 25),
		# Issue 62: the Priest's no-cost basic attack. Same range and travel
		# time as priest_smite so it needs no separate approach logic, weaker
		# (power_scale 0.5 vs 0.9) so Smite still has a reason to be cast once
		# Mana allows it. Without this the Priest had nothing to do the moment
		# Mana ran low: priest_heal and priest_smite both cost resource, and
		# DefaultBehavior's fallback (the first non-heal action in the class's
		# own list, see starting_classes.gd) would keep ordering an unaffordable
		# Smite forever rather than actually landing a hit.
		_projectile(_action(&"priest_bolt", "Bolt", "A ranged bolt of divine light dealing damage at up to 220 units. Costs nothing.", CG.DamageType.DIVINE, 220.0, 8, 10, 0.5, 0, 0, true), 65.0),
		_projectile(_action(&"priest_smite", "Smite", "A ranged bolt of divine light dealing damage at up to 220 units.", CG.DamageType.DIVINE, 220.0, 10, 10, 0.9, 15, 0, true), 65.0),
		# The Priest's two buff spells, per the player's own direction ("one
		# for speed, one for resistance") -- both target an ally within 220
		# units, the same range as Heal and Smite, so they need no separate
		# approach logic. Built with `_action_ally_buff`, not `_action_status`
		# -- `_action_status` hardcodes cooldown_ticks to 0, which is the
		# exact bug `warrior_block` shipped with (see its own comment): an
		# `always`-conditioned, affordable, zero-cooldown action wins every
		# decide() tick forever, so a Priest with Mana to spare would recast
		# a buff on cooldown-0 endlessly and never reach Smite or fall
		# through to Bolt. cooldown_ticks matches duration_ticks instead,
		# same shape `_action_self_buff` already uses for a self-targeted
		# buff -- this is that same fix, generalised to an ally-targeted one.
		#
		# priest_haste: HASTE, Balance.HASTE_TICK_SCALE (0.7) already scales
		# wind-up and recovery through the SimDeps seam -- this is the first
		# thing in the game to grant it. 5s duration/cooldown, matching every
		# other timed status in the bestiary (MARKED, SLOWED).
		_action_ally_buff(&"priest_haste", "Haste", "Speeds up an ally's actions by 30% for 5 seconds. Costs 15 Mana.", CG.DamageType.DIVINE, 220.0, 8, 10, 15, CG.Status.HASTE, 150),
		# priest_ward: SHIELD, Balance.damage_reduction already reads it
		# (STATUS_SHIELD_REDUCTION, 25%) -- content-inert until now, the same
		# state SHIELDING was in before issue 52 gave it a real grantor.
		_action_ally_buff(&"priest_ward", "Ward", "Reduces damage taken by an ally by 25% for 5 seconds. Costs 15 Mana.", CG.DamageType.DIVINE, 220.0, 8, 10, 15, CG.Status.SHIELD, 150),

		_projectile(_action_splash(&"geyser_blast", "Geyser Blast", "A splash of scalding water that damages every enemy within 50 units of the impact point, up to 200 units away. Costs 20 Mana.", CG.DamageType.WATER, 200.0, 50.0, 12, 12, 0.8, 20, true), 65.0),
		_projectile(_action(&"geyser_scald", "Scald", "A focused burst of fire at a single target up to 200 units away. Costs 15 Mana.", CG.DamageType.FIRE, 200.0, 8, 8, 1.0, 15, 0, true), 65.0),

		# Issue 12: siege_shot and siege_barrage retired along with the range
		# that made the class mandatory (260, past every enemy's own reach --
		# see issue 25/31). The Siege Master is a spotter/engineer now,
		# per the player's own spec, and both of its new actions put
		# something in the room's reach: a marked target is a target the
		# room can still see, and an engine is a unit the room can attack.
		#
		# Issue 62: the Siege Master's no-cost basic attack. Both existing
		# actions cost Mana (spotter_mark 15, build_siege_engine 20), so a
		# Siege Master that entered a room low on Mana had nothing affordable
		# to do -- the exact trap the issue names, measured at zero damage
		# dealt across a whole fight for three of four Siege Masters before
		# this. 200 range matches the room's own ranged band (geyser_blast,
		# priest_smite, cultist_bolt) rather than reaching past it, same
		# reasoning as spotter_mark's own range choice below.
		_projectile(_action(&"siege_master_shot", "Shot", "A ranged shot dealing damage at up to 200 units. Costs nothing.", CG.DamageType.PHYSICAL, 200.0, 8, 10, 1.0, 0, 0, true), 65.0),
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
		_projectile(_action_status(&"spotter_mark", "Spotter's Mark", "Marks a target within 220 units, reducing its damage reduction by 25 percentage points for 5 seconds.", CG.DamageType.PHYSICAL, 220.0, 10, 10, 1.0, 15, CG.Status.MARKED, 150, true), 65.0),
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
		_action_summon(&"build_siege_engine", "Build Siege Engine", "Spends 3 seconds building a Siege Engine with 140 health that then fights at range on its own. Costs 20 Mana.", 90, 20, 20, &"siege_engine"),

		# Issue 62: abomination_claw, restored. The player's own direction --
		# "Restore abomination_claw" -- reversing issue 52's retirement of it.
		# Costs no Rage, same shape (and same numbers) as before issue 52
		# removed it: a melee hit that also applies POISON, so a Rage-starved
		# Abomination (hook and grapple both cost Rage, and Rage only fills
		# from a landed hit) still has something to do and a way back into
		# its own resource economy, the exact trap the issue names. Placed
		# first in starting_classes.gd's own action list so DefaultBehavior's
		# fallback picks this rather than an unaffordable hook, mirroring
		# warrior_strike's own position for the same reason.
		_action_status(&"abomination_claw", "Claw", "A melee strike that poisons the target for 9% of its max health per second, for 3 seconds. Costs nothing.", CG.DamageType.PROFANE, 45.0, 7, 9, 1.0, 0, CG.Status.POISON, 90),
		# Issue 52: the Abomination's hook and grapple, per the player's own
		# spec -- "a mid-range hook that drags enemies in" plus a follow-up
		# so a hooked target cannot just walk back out. Both already deal
		# damage on top of their control role (pull / slow), per the
		# player's own issue-62 direction that they keep it.
		#
		# abomination_hook: 140 range sits deliberately between this
		# bestiary's melee band (40-45) and its ranged band (200-270) --
		# "far enough to open a fight, close enough to be a commitment," per
		# the player's own words. pull_distance 100 drags a target from the
		# hook's own maximum range to just outside abomination_grapple's 45-
		# unit melee reach, so a hook lands its target close enough that one
		# more step (or a second hook) closes the gap rather than needing to
		# close 140 units on foot. requires_line_of_sight and
		# projectile_speed 65.0, same as every other real ranged action in
		# the game (issue 18) -- a hook is a thrown line, not an instant
		# grab, and giving it a real travel time is what makes SHIELDING
		# able to intercept it too, same as any other travelling shot.
		_projectile(_pull(_action(&"abomination_hook", "Hook", "A profane tendril that deals damage and pulls the target 100 units toward the caster. Reaches 140 units. Costs 15 Rage.", CG.DamageType.PROFANE, 140.0, 10, 12, 1.4, 15, 0, true), 100.0), 65.0),
		# abomination_grapple: melee range (45, matching this bestiary's
		# other melee actions), applies SLOWED so a target the hook just
		# dragged in cannot simply walk back out before the Abomination's
		# next action is ready -- Balance.slowed_speed_scale, issue 52's own
		# content half of issue 14's simulation seam. Duration 150 ticks
		# (5s), the same length as spotter_mark's MARKED -- long enough to
		# matter across several of the Abomination's own attacks, not so
		# long it never falls off between engagements.
		_action_status(&"abomination_grapple", "Grapple", "A crushing melee grip that deals damage and slows the target's movement by 50% for 5 seconds. Costs 20 Rage.", CG.DamageType.PROFANE, 45.0, 8, 10, 2.8, 20, CG.Status.SLOWED, 150),

		_action(&"goblin_stab", "Stab", "A melee jab dealing damage at up to 40 units.", CG.DamageType.PHYSICAL, 40.0, 6, 6, 1.0, 0, 0),
		_projectile(_action(&"goblin_arrow", "Arrow", "A ranged shot dealing damage at up to 200 units.", CG.DamageType.PHYSICAL, 200.0, 8, 8, 1.0, 0, 0, true), 65.0),
		_action(&"ghoul_maul", "Maul", "A melee blow at up to 45 units, with a 0.5-second wind-up.", CG.DamageType.PHYSICAL, 45.0, 14, 14, 1.0, 0, 0),
		# Issue 23: the bestiary's status user. Profane -> POISON per README.md.
		_projectile(_action_status(&"cultist_bolt", "Dark Bolt", "A ranged bolt at up to 200 units that poisons the target for 9% of its max health per second, for 3 seconds.", CG.DamageType.PROFANE, 200.0, 10, 10, 0.7, 0, CG.Status.POISON, 90, true), 65.0),

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
		_action(&"warden_axe", "Executioner's Axe", "A melee swing at up to 55 units, with a 0.7-second wind-up.", CG.DamageType.PHYSICAL, 55.0, 20, 22, 2.4, 0, 0),
		_projectile(_action(&"warden_chain_toss", "Chain Toss", "A ranged attack at up to 270 units.", CG.DamageType.PHYSICAL, 270.0, 16, 18, 1.0, 0, 0, true), 65.0),

		# Issue 12: the siege engine's own attack, once built. Ranged and
		# reliable rather than powerful on its own -- the Siege Master's
		# contribution is having two of these on the field, not one hitting
		# hard. 200 range, same band as the room's other ranged casters.
		_projectile(_action(&"siege_engine_bolt", "Engine Bolt", "A ranged attack at up to 200 units.", CG.DamageType.PHYSICAL, 200.0, 12, 12, 1.0, 0, 0, true), 65.0),

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

## Issue 30: self-targeted (range 0.0, no line-of-sight check, no damage --
## same "the status is the whole effect" shape _action_summon already uses)
## application of TAUNTING, with a real taunt_radius and a cooldown so it
## cannot be refreshed before it has actually lapsed. `_action_status` does
## not cover this: it has no `taunt_radius` or `cooldown_ticks` parameter,
## and every existing caller of it is a damage-dealing status application
## where those two would not mean anything.
## Issue 18/content: wraps any ActionDef with a real travel speed rather than
## the instant-by-default 0.0. 65.0 world units/tick for every real ranged
## action in the game, found empirically rather than picked -- a throwaway
## probe (not committed) fired at a target that flees directly away from the
## shooter the instant the shot launches, every tick, at 7.0 units/tick
## (faster than any real unit's own move_speed today). Below 40 (this
## bestiary's shortest real range, goblin_arrow at 200) and below 55
## (warden_chain_toss at 270, the longest range in the game) respectively,
## that worst case always misses -- not "harder to hit", genuinely
## unhittable, because the projectile's frozen aim_point is a fixed distance
## from the shooter and a target retreating fast enough relative to the
## shot's own speed can keep the gap at expiry wider than its own hit
## radius for the whole flight. 65.0 clears both thresholds with real
## margin (a real unit fleeing this fast does not exist today), while still
## giving projectiles real travel time to matter -- a 200-range shot takes
## ~3 ticks, a 270-range one ~4. This is also what makes SHIELDING's own
## interception real: at projectile_speed 0.0 there is nothing in flight for
## a shielder to intercept.
static func _projectile(a: ActionDef, speed: float) -> ActionDef:
	a.projectile_speed = speed
	return a

## Issue 52/14: wraps an ActionDef with a real pull, same "the mechanism was
## always inert-by-default, content decides who uses it" pattern _projectile
## established for issue 18. `distance` is how far the target is dragged
## toward the caster, in world units -- see ActionDef.pull_distance's own
## doc comment for why the simulation (not content) does the dragging.
static func _pull(a: ActionDef, distance: float) -> ActionDef:
	a.pull_distance = distance
	return a

## Issue 52: a self-targeted status application whose cooldown genuinely
## matches its own duration, the same shape `_action_taunt` already uses --
## pulled out as its own helper rather than copied a second time. Deliberately
## NOT `_action_status`: that helper hardcodes cooldown_ticks to 0, which is
## correct for every existing caller (each one is gated by something else --
## a resource cost, a plan's own range condition, or simply being a damage-
## dealing hit rather than a repeatable self-buff) and wrong for an
## `always`-conditioned, zero-cost, self-targeted buff, which would win every
## decide() tick forever with no cooldown of its own. See warrior_block's own
## comment for the real fight this was found in.
static func _action_self_buff(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, wind_up: int, recover: int, status: CG.Status, duration_ticks: int) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, 0.0, wind_up, recover, 0.0, 0, duration_ticks)
	a.applies_status_enabled = true
	a.applies_status = status
	a.status_duration_ticks = duration_ticks
	return a

## Same reasoning as `_action_self_buff` (cooldown matches duration, not
## `_action_status`'s hardcoded 0), for an ally-targeted buff instead of a
## self-targeted one: range_units and resource_cost are real here, since an
## ally buff has to reach its target and, unlike a shout or a taunt, is worth
## gating behind Mana so it competes with the class's other spells for the
## same pool. `requires_los` deliberately left at its default (false), same
## exception `priest_heal` already carries: support reaching an ally, not a
## shot at an enemy.
static func _action_ally_buff(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, resource_cost: int, status: CG.Status, duration_ticks: int) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, 0.0, resource_cost, duration_ticks)
	a.applies_status_enabled = true
	a.applies_status = status
	a.status_duration_ticks = duration_ticks
	return a

static func _action_taunt(id: StringName, display_name: String, description: String, wind_up: int, recover: int, taunt_radius: float, duration_ticks: int) -> ActionDef:
	var a := _action(id, display_name, description, CG.DamageType.PHYSICAL, 0.0, wind_up, recover, 0.0, 0, duration_ticks)
	a.applies_status_enabled = true
	a.applies_status = CG.Status.TAUNTING
	a.status_duration_ticks = duration_ticks
	a.taunt_radius = taunt_radius
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
