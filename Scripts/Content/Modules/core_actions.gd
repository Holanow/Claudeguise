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

## Travel speed, in world units per tick, for every real ranged action on either
## side. One constant rather than the literal repeated at twelve call sites: it
## was already the same number everywhere, and the player has now asked for it to
## move twice.
##
## **32.5, halved from 65.0 at the player's direct request: "can we cut
## specifically projectile speed in half again, it's just hard to read."**
##
## Wall-clock, which is what they are reading and what the number below does not
## say on its own: this is per *tick*, and `TICKS_PER_SECOND` already went 30 to
## 15, so a shot is now four times slower on screen than when projectiles landed,
## not twice. 32.5/tick is 487 units/second, and the arena is 960 wide.
##
## **This value has a floor as well as a ceiling, and 32.5 is below the floor the
## old comment here claimed.** The ceiling is tunnelling: a shot moving further
## per tick than a target's diameter can step past it between checks. The floor is
## the frozen aim point -- `CombatSim._spawn_projectile` freezes `aim_point` at
## launch and never homes, so a target retreating in a straight line stays outside
## its own hit radius for the whole flight whenever
## `speed * target_radius < range * flee_speed`. The previous comment picked 65.0
## specifically to clear that (~40 at range 200, ~55 at range 270, against a
## hypothetical 7.0/tick runner). Halving does not clear it against *real* units:
## a fleeing `goblin_archer` (move_speed 3.2, radius 11) shot at from 200 units
## needs 58.2 and now gets 32.5.
##
## That is a real cost and it is not hidden here: the player asked for legibility
## and the price is more misses against anything that runs. What it cost in win
## rate is measured in issue 93's PR rather than corrected for by moving damage.
const RANGED_PROJECTILE_SPEED := 32.5

## Issue 132: *"The default attack of any magic class should restore a small
## amount of mana."*
##
## **Derived from a stated ratio rather than tuned to an outcome, which matters
## while balance is frozen: five basic attacks buy one spell.** Smite costs 15,
## so 3 per landed Bolt is five Bolts per Smite. Blast costs 20, so it is closer
## to seven per Blast. Nothing here was chosen by running a win table, and no
## existing number moved.
##
## For scale: a Priest holds about 100 Mana, a bolt occupies 18 ticks (1.2s), and
## `MANA_REGEN_PERCENT_PER_SECOND` is 4.0, so passive regen is about 4 Mana a
## second. Attacking therefore roughly doubles a caster's income instead of
## replacing it, which is the point -- **a caster that stands still should still
## be the one that runs dry.**
##
## **Only the two MAGICAL basic attacks carry it.** `siege_master_shot` does not:
## the Siege Master is a Mana class but a MARTIAL one, and the player said "any
## magic class". That distinction is the whole reason this is a per-action field
## rather than a per-resource-kind rule -- see `ActionDef.restores_resource`.
const MAGIC_BASIC_ATTACK_MANA := 3

## "Reaches anywhere in the room", expressed as a real number.
##
## Issue 93, the player's spec for the Siege Engine: unlimited range. A literal
## `INF` would be the honest spelling of that and it is deliberately not used --
## every range comparison, distance sort and `_target_in_range` check in the
## project takes a float and works unchanged against a large finite one, whereas
## `INF` would make each of them a place someone has to think about infinity.
##
## The arena is `2 * CG.ARENA_HALF_WIDTH` by `2 * CG.ARENA_HALF_HEIGHT`, so the
## true maximum distance between two points in it is the diagonal,
## sqrt(960^2 + 540^2) = 1101.4. 1200.0 sits above that with margin and is not
## derived from the CG constants here because GDScript has no constant-expression
## `sqrt`. **The guard against that going stale is a test, not this comment:**
## `Tests/test_content_actions.gd` recomputes the diagonal from `CG` and asserts
## this still exceeds it, so resizing the arena fails loudly instead of silently
## giving artillery a range that no longer covers the room.
const ARENA_SPAN := 1200.0

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
		# Issue 79: cost 60 -> 25. This action fired zero times across 210
		# real fights, and the cause was not tuning or plan priority: the
		# Warrior's Rage pool has a *maximum* of 40. `Balance.max_resource`
		# is `30 + ATN*8 + INT*2`, and the Warrior is ATN 1 / INT 1, so 40 --
		# full at fight start and capped there for the whole fight. A
		# 60-cost action was unaffordable by construction for every Warrior
		# in the game, in every fight, forever. Measured with a throwaway
		# probe stepping three real encounters tick by tick (not committed):
		# 0 ticks at Rage >= 60 in any of them.
		#
		# 20 of a 40 pool, refilled at `RAGE_GAIN_PERCENT_PER_HIT` (18% of
		# max, so 7.2) per landed hit: roughly one Execute per three landed
		# Strikes. Deliberately not fixed by raising the Warrior's ATN
		# instead -- that inflates what every Rage cost means at once, and
		# hands a martial class a caster's pool to correct one number.
		#
		# 20 and not 25, and its plan fires only at a full 40 (see
		# `warrior_execute_finisher`), so Execute always leaves exactly one
		# warrior_guard payable behind it. **That pairing is the tidier
		# economy and it is not a fix for anything -- disclosing the
		# hypothesis that failed rather than only the number that came out
		# of it.** Making Execute reachable costs the one real party whose
		# only change is this action (abomination/siege_master/priest/
		# warrior) a large part of its Warden win rate, and Rage contention
		# with Guard was the obvious explanation. A probe counting casts over
		# the same 20 seeds killed it: at 25/threshold 35 that party guarded
		# 60 times and won 7/20; at 20/threshold 40 it guarded *98* times,
		# survived longer (14 Warrior deaths instead of 20) and won 8/20.
		# More Guard, more survival, no more wins. The real mechanism is
		# still unknown and is on the board for rook rather than tuned
		# around here -- see the full 60-seed table in the pull request.
		#
		# The cost was only half of it. See `warrior_execute_finisher` in
		# PresetPlans.gd for the other half: nothing chose this action
		# either, at any price.
		_action(&"warrior_execute", "Execute", "A heavy melee blow that deals twice the damage of a Strike. Costs 20 Rage.", CG.DamageType.PHYSICAL, 40.0, 8, 10, 2.0, 20, 40),
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

		# Issue 99: the Warrior's self-sustain, replacing Directional Block in
		# this class's kit. The player's own call -- "Something like the
		# projectile block the warrior has now would belong to a shield
		# instead of the class. You should then replace the warrior skill
		# with some kind of self-sustain, like a second wind that heals him
		# for a bit."
		#
		# **`warrior_block` is not deleted.** It moves onto `plate_mail` via
		# `granted_actions` (issue 100), which is where README's own armor
		# table always had it: `Plate Mail | Tank | Block`. It stays in this
		# file, unchanged, because it is still a real action -- it is just no
		# longer something the class carries for free.
		#
		# Numbers, sized against this class rather than picked. The Warrior
		# has STR 9, so `Balance.attack_power` is 9 * 1.9 = 17.1, and
		# `max_hp` is 60 + 14*12 + 9*2 = 246. power_scale 3.0 heals ~51, a
		# fifth of the bar: "for a bit", not a full reset, and well short of
		# out-healing the ~58 a Warden swing lands.
		#
		# **cooldown 300 ticks (20s) is what makes it a second wind rather
		# than a heal.** Without it this is a zero-cooldown self-heal on a
		# class whose Rage refills from every landed hit, which is exactly
		# the failure `warrior_block` shipped with (see its own comment
		# above): a cheap self-targeted action with no cooldown wins every
		# decide() tick forever and the class stops doing anything else.
		#
		# Costs 15 Rage rather than the 20 that Guard and Execute cost. Rage
		# only fills from landed hits, so a Warrior who is losing -- the one
		# this exists for -- is precisely the one who has not been landing
		# hits. 20 made it unaffordable in the moment it was needed; 15
		# leaves it reachable without making it free.
		_action_self_heal(&"warrior_second_wind", "Second Wind", "Draws on a reserve of stamina to heal the Warrior for a moderate amount. Can only be done occasionally. Costs 15 Rage.", CG.DamageType.PHYSICAL, 15, 12, 2.2, 15, 450),

		_action_heal(&"priest_heal", "Heal", "Restores health to an ally within 220 units.", CG.DamageType.DIVINE, 220.0, 8, 10, 1.4, 25),
		# Issue 62: the Priest's no-cost basic attack. Same range and travel
		# time as priest_smite so it needs no separate approach logic, weaker
		# (power_scale 0.5 vs 0.9) so Smite still has a reason to be cast once
		# Mana allows it. Without this the Priest had nothing to do the moment
		# Mana ran low: priest_heal and priest_smite both cost resource, and
		# DefaultBehavior's fallback (the first non-heal action in the class's
		# own list, see starting_classes.gd) would keep ordering an unaffordable
		# Smite forever rather than actually landing a hit.
		_restores(_projectile(_action(&"priest_bolt", "Bolt", "A ranged bolt of divine light dealing damage at up to 220 units. Costs nothing and returns 3 Mana when it lands.", CG.DamageType.DIVINE, 220.0, 8, 10, 0.5, 0, 0, true), RANGED_PROJECTILE_SPEED), MAGIC_BASIC_ATTACK_MANA),
		_projectile(_action(&"priest_smite", "Smite", "A ranged bolt of divine light dealing damage at up to 220 units.", CG.DamageType.DIVINE, 220.0, 10, 10, 0.9, 15, 0, true), RANGED_PROJECTILE_SPEED),
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

		# Issue 79: the Geysermancer's no-cost basic attack, the third and last
		# class to get one. The player's standing instruction, said twice --
		# "every unit should have some kind of basic attack", "the basic
		# attack should cost no resource" -- and this class was missed when
		# that was applied to the Abomination and again when it was applied
		# to the Priest and the Siege Master (both issue 62). Both of its
		# actions cost Mana, so a Geysermancer out of Mana stood still.
		#
		# 200 range and the shared RANGED_PROJECTILE_SPEED, matching geyser_blast and geyser_scald
		# exactly, so it needs no separate approach logic. power_scale 0.5,
		# half of Scald's 1.0, so Scald still has a reason to be cast the
		# moment Mana allows it -- the same relationship priest_bolt (0.5)
		# has to priest_smite (0.9). WATER rather than FIRE: that is this
		# class's primary damage type per its own ClassDef, and Scald is
		# already the fire one.
		#
		# Issue 129: this action is granted by the Orb rather than owned by
		# the class, and the paragraph that used to sit here explaining that
		# it had to be *placed first* in `starting_actions` is gone with the
		# rule it described. `DefaultBehavior` now falls back to the cheapest
		# action that can damage, so what makes this the fallback is that it
		# is free, not where it sits in a list.
		_restores(_projectile(_action(&"geyser_spout", "Spout", "A jet of scalding water dealing damage at up to 200 units. Costs nothing and returns 3 Mana when it lands.", CG.DamageType.WATER, 200.0, 8, 10, 0.5, 0, 0, true), RANGED_PROJECTILE_SPEED), MAGIC_BASIC_ATTACK_MANA),
		_projectile(_action_splash(&"geyser_blast", "Geyser Blast", "A splash of scalding water that damages every enemy within 50 units of the impact point, up to 200 units away. Costs 20 Mana.", CG.DamageType.WATER, 200.0, 50.0, 12, 12, 0.8, 20, true), RANGED_PROJECTILE_SPEED),
		# Issue 79: numbers unchanged. This action also fired zero times in 210
		# real fights, and nothing about the action itself was the cause --
		# its plan was strictly dominated by the one above it. See
		# `geyser_blast_cluster` and `geyser_scald_finisher` in
		# PresetPlans.gd, which is where the whole fix lives.
		_projectile(_action(&"geyser_scald", "Scald", "A focused burst of fire at a single target up to 200 units away. Costs 15 Mana.", CG.DamageType.FIRE, 200.0, 8, 8, 1.0, 15, 0, true), RANGED_PROJECTILE_SPEED),
		# Issue 87: the player's own "Geysermancer can do debuff removal", and
		# the thing that makes this class's SUPPORT tag true -- until this it
		# had three actions and all three were pure damage.
		#
		# Deliberately narrow on purpose, and the numbers come from swift's
		# measurement rather than from what the ability sounds like it should
		# cost. A Geysermancer alive and within its own 200 units of an
		# afflicted ally covers **3.1% of ticks** of real play, and the only
		# harmful status anything in this game applies to a player unit today is
		# POISON (issue 90). So every number here is chosen to make the ability
		# cheap to own rather than strong: it must not take turns away from
		# Blast, Scald and Spout on the other 96.9%.
		#
		# `heals = true` with `power_scale 0.0`: the strip is the whole effect,
		# and `CombatSim._apply_action_effect` emits no HEAL event when the
		# applied amount is 0, so this adds no line to the log except the
		# STATUS_EXPIRED it exists to produce. `heals = false` would take the
		# damage branch instead and emit a DAMAGE event for 0 at an *ally*.
		# 200 range and instant, not `_projectile`: every support action in the
		# game (priest_heal, priest_haste, priest_ward) is instant, and a
		# travelling cleanse could MISS an ally who stepped away during a flight
		# that exists only to look like something.
		# 10 Mana sits below Scald's 15, so the class's own descending ladder in
		# PresetPlans.gd keeps working: this is affordable in a window where the
		# damage spells are not, and cheap enough not to compete with them.
		# cooldown 60 ticks (4s) is the real bound on the cost, and it is not
		# decoration: an ability with no cooldown re-fires the moment an enemy
		# re-applies POISON, and the wind-up plus recovery it spends is time the
		# Geysermancer is not dealing damage whether it strips anything or not.
		# swift measured that shape directly -- an `always`-conditioned probe
		# cleanse cast 4055 times to strip 8 statuses and cut Blast 593->101 and
		# Scald 676->32. The condition (PresetPlans.gd) is the first defence
		# against that and this is the second.
		_action_cleanse(&"geyser_cleanse", "Scour", "Boils every harmful effect off an ally within 200 units. Costs 10 Mana.", 200.0, 8, 10, 10, 60),

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
		_projectile(_action(&"siege_master_shot", "Shot", "A ranged shot dealing damage at up to 200 units. Costs nothing.", CG.DamageType.PHYSICAL, 200.0, 8, 10, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),
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
		_projectile(_action_status(&"spotter_mark", "Spotter's Mark", "Marks a target within 220 units, reducing its damage reduction by 25 percentage points for 5 seconds.", CG.DamageType.PHYSICAL, 220.0, 10, 10, 1.0, 15, CG.Status.MARKED, 150, true), RANGED_PROJECTILE_SPEED),
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
		#
		# Issue 93: capped at 2 live engines. The player's spec, and the cap is
		# not only a limit on engines -- it is what pays for the marking the
		# engines now depend on. This action and spotter_mark compete for one
		# Mana pool and this one wins nearly every tick it is affordable
		# (PresetPlans orders build first), which is why spotter_mark was
		# measured landing 0.34 times per fight before this. Every capped-out
		# tick is a tick the build plan falls through and the mark plan fires.
		# That only works because the cap is enforced where the action is
		# *chosen* (PlanInterpreter/DefaultBehavior) rather than where the summon
		# spawns: refusing at spawn time would still burn 20 Mana and a 90-tick
		# wind-up, making marking rarer instead of more frequent.
		_summon_cap(_action_summon(&"build_siege_engine", "Build Siege Engine", "Spends 3 seconds building a Siege Engine with 140 health. It cannot move and only fires at enemies you have marked. Two at most. Costs 20 Mana.", 90, 20, 20, &"siege_engine"), 2),

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
		# the shared RANGED_PROJECTILE_SPEED, same as every real ranged action in
		# the game (issue 18) -- a hook is a thrown line, not an instant
		# grab, and giving it a real travel time is what makes SHIELDING
		# able to intercept it too, same as any other travelling shot.
		_projectile(_pull(_action(&"abomination_hook", "Hook", "A profane tendril that deals damage and pulls the target 100 units toward the caster. Reaches 140 units. Costs 15 Rage.", CG.DamageType.PROFANE, 140.0, 10, 12, 1.4, 15, 0, true), 100.0), RANGED_PROJECTILE_SPEED),
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
		_projectile(_action(&"goblin_arrow", "Arrow", "A ranged shot dealing damage at up to 200 units.", CG.DamageType.PHYSICAL, 200.0, 8, 8, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),
		_action(&"ghoul_maul", "Maul", "A melee blow at up to 45 units, with a 0.5-second wind-up.", CG.DamageType.PHYSICAL, 45.0, 14, 14, 1.0, 0, 0),
		# Issue 23: the bestiary's status user. Profane -> POISON per README.md.
		_projectile(_action_status(&"cultist_bolt", "Dark Bolt", "A ranged bolt at up to 200 units that poisons the target for 9% of its max health per second, for 3 seconds.", CG.DamageType.PROFANE, 200.0, 10, 10, 0.7, 0, CG.Status.POISON, 90, true), RANGED_PROJECTILE_SPEED),

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
		_projectile(_action(&"warden_chain_toss", "Chain Toss", "A ranged attack at up to 270 units.", CG.DamageType.PHYSICAL, 270.0, 16, 18, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),

		# Issue 93: the siege engine's own attack, rebuilt as artillery at the
		# player's spec -- "give the engines infinite range and a lower than
		# average attack speed", "but they only fire on marked targets", "they
		# should also be pretty much stationary".
		#
		# **Range ARENA_SPAN, not INF.** A real float keeps every existing
		# range comparison, distance sort and `_target_in_range` check working
		# unchanged; nothing in the project has to learn what infinity means. It
		# is a constant rather than a literal so the guard test can prove it
		# still exceeds the real arena diagonal if anyone resizes the room.
		#
		# **wind_up 45 / recover 15, a 60-tick cycle: 4.0 seconds, 15.0 shots
		# per minute.** Measured against every other ranged action rather than
		# picked: their cycles are 16 to 34 ticks, mean 20.4 (44.1 shots/min),
		# and the slowest thing in the game before this was warden_chain_toss at
		# 34 ticks (26.5/min). So this is 2.9x slower than the ranged average
		# and 1.8x slower than the previous slowest, which is what "lower than
		# average" has to mean for a weapon that can hit anywhere. Most of it
		# is wind_up rather than recover on purpose: ActionDef.wind_up_ticks is
		# the interruptible, readable half, and a siege piece visibly cranking
		# for three seconds is the whole read.
		#
		# **The one that decides whether any of this matters: only fires at a
		# MARKED enemy.** `spotter_mark` stops being a damage-amp bolted onto a
		# summoner and becomes the engine's targeting system, which makes the
		# Siege Master one class instead of two unrelated halves.
		#
		# Cost of the pair, stated rather than buried: at ARENA_SPAN the bolt is
		# in flight ~34 ticks (1101 / RANGED_PROJECTILE_SPEED), so a maximum-
		# range shot is over 5 seconds from decision to impact, against a frozen
		# aim point that does not home. Long shots at anything mobile will miss
		# often. That is measured in the PR, not corrected for here.
		_projectile(_marked_only(_action(&"siege_engine_bolt", "Engine Bolt", "A ranged attack that reaches anywhere in the arena, but only at an enemy the Siege Master has marked. Fires once every 4 seconds.", CG.DamageType.PHYSICAL, ARENA_SPAN, 45, 15, 1.0, 0, 0, true)), RANGED_PROJECTILE_SPEED),

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

## Issue 99: a heal a unit casts on itself, with a real cooldown.
##
## `_action_heal` does not cover this and wrapping it would be worse: it takes a
## `range_units` an ally heal needs and has no `cooldown_ticks` parameter, and
## every existing caller of it is a ranged heal aimed at somebody else.
##
## **`range_units` 0.0 is what makes it self-only, and that is a real statement
## rather than a placeholder.** `DefaultBehavior` reads it: a heal with no reach
## can only be cast on the caster, so the neediest-ally search is restricted to
## the caster itself. Without that, a Warrior carrying this would walk toward a
## hurt Priest forever trying to get in range of a heal that has none.
##
## `requires_line_of_sight` stays false, the same exception `priest_heal` and
## `geyser_cleanse` already carry: nothing stands between a unit and itself.
static func _action_self_heal(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, 0.0, wind_up, recover, power_scale, resource_cost, 0)
	a.heals = true
	a.cooldown_ticks = cooldown_ticks
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
## the instant-by-default 0.0, which is what makes SHIELDING's interception real
## -- at projectile_speed 0.0 there is nothing in flight for a shielder to catch.
##
## **The paragraph that used to live here justified 65.0 as clearing a lower
## bound, and issue 93 halved the number below that bound at the player's
## request. It is rewritten rather than left standing, because a comment
## defending a value the file no longer holds is worse than none.** The bound
## itself was correct and is now stated where the value lives:
## `RANGED_PROJECTILE_SPEED` at the top of this file.
static func _projectile(a: ActionDef, speed: float) -> ActionDef:
	a.projectile_speed = speed
	return a

## Issue 132: the mana a magic class's default attack returns when it lands.
## Same inert-by-default shape as `_projectile` and `_marked_only` -- the field
## is 0 on every other action.
static func _restores(a: ActionDef, amount: int) -> ActionDef:
	a.restores_resource = amount
	return a

## Issue 93: wraps an ActionDef so it may only be aimed at an enemy carrying
## MARKED. Same inert-by-default, content-decides-who-uses-it shape as
## `_projectile` and `_pull`: the field is false on every other action, so this
## adds a capability without changing one existing behaviour.
##
## Only `siege_engine_bolt` sets it, and that is the whole of the Siege Master's
## rebuild -- the engine cannot choose its own targets, the Siege Master
## designates them with `spotter_mark`. The gate is enforced in
## `Scripts/Plans/DefaultBehavior.gd`, which is where a unit picks what to shoot
## at; an engine with nothing marked holds fire rather than shooting at the
## nearest thing.
static func _marked_only(a: ActionDef) -> ActionDef:
	a.requires_marked_target = true
	return a

## Issue 93: caps how many live summons this action may have on the field at
## once. Built as a property of the summoning action rather than a special case
## for the Siege Master, because `summons_unit_id` is generic on either team and
## the next summoner will want the same thing -- there was no cap mechanism
## anywhere before this (`grep max_summon|summon_limit` returned nothing).
##
## 0 means uncapped, which is every other action, so this is additive.
static func _summon_cap(a: ActionDef, cap: int) -> ActionDef:
	a.max_active_summons = cap
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

## Issue 87: an ally-targeted action whose entire effect is
## `cleanses_harmful` -- no damage, no heal, no status of its own. Same
## "the mechanism is the whole effect" shape `_action_summon` already uses for
## `summons_unit_id`.
##
## `heals` is true so `_apply_action_effect` takes the heal branch and not the
## damage one; at `power_scale 0.0` that branch applies 0 and emits nothing,
## which is exactly what is wanted. It is NOT set to make `DefaultBehavior` aim
## this at an ally: the fallback path must never reach for this action at all,
## and does not -- see starting_classes.gd's own note on where this sits in the
## Geysermancer's action list.
##
## Unlike `_action_status`, the cooldown is a real parameter rather than a
## hardcoded 0, for the reason `_action_self_buff` already records: an action
## that costs little and is worth casting on sight needs a floor on how often
## it can take the caster's turn.
static func _action_cleanse(id: StringName, display_name: String, description: String, range_units: float, wind_up: int, recover: int, resource_cost: int, cooldown_ticks: int) -> ActionDef:
	var a := _action(id, display_name, description, CG.DamageType.WATER, range_units, wind_up, recover, 0.0, resource_cost, cooldown_ticks)
	a.heals = true
	a.cleanses_harmful = true
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
