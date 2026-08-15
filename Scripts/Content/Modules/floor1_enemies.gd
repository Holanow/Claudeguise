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

## Ranged projectile speed. Duplicated from `core_actions.gd` rather than
## reached into: that file's copy is a `const` on another session's module and
## reading a neighbour's private constant is how two numbers start disagreeing
## silently. If issue 93's speed moves again, this moves with it, and the
## reason it is worth having twice is that a mark with no travel time cannot be
## shielded, dodged or seen coming.
const RANGED_PROJECTILE_SPEED := 32.5

## **Issue #121's enemy actions live here, not in `core_actions.gd`, and I was
## wrong about that for two days.**
##
## `Registry.gd`'s module contract gives *every* module its own `actions()`, and
## this one has always returned `[]`. I posted these three definitions on the
## board asking finch to apply them to `core_actions.gd`, blocked myself on a
## file another session had three branches open in, and never read the eleven
## lines that said I did not need it. A floor-1-enemy-only action belongs in
## the floor-1 enemy module beside the enemy that carries it.
##
## The pre-existing enemy actions (`goblin_stab`, `ghoul_maul`,
## `warden_axe` ...) are left where they are. Moving them would be a rename
## across an ownership boundary for tidiness, which is exactly the churn
## `ENGINEER.md` says not to create.
static func actions() -> Array[ActionDef]:
	return [
		## **The first STUN source in the game**, and it only became worth
		## authoring on 2026-08-14. STUN existed and worked -- a stunned unit
		## is skipped in `_decide_phase` -- but it could not interrupt a
		## committed wind-up, which was issue 10's deliberate decision. I
		## refused to write this enemy against that, because "a big heavy guy
		## that stuns units" whose stun cannot stop a cast is a much smaller
		## thing than the words promise. The player overturned issue 10 and
		## swift shipped `CG.EventKind.INTERRUPTED`; this is what that was for.
		##
		## 8 ticks, not 7. The player asked for 0.5 seconds and
		## `CG.TICKS_PER_SECOND` is 15, so 0.5s is 7.5 ticks. Rounding down
		## gives a stun one tick shorter than this action's own 16-tick
		## wind-up rhythm and, more to the point, `_tick_statuses` checks
		## expiry against `state.tick + duration`, so a stun that rounds down
		## is a stun that can end before the victim's next decide phase and do
		## nothing at all. Rounded up on purpose.
		##
		## power_scale 2.0 against `attack_power` 24 makes this a real blow
		## rather than a stun stapled to a tap: an enemy whose whole identity
		## is "slow, tough, hits once and it hurts" has to hurt.
		_action_status(&"brute_slam", "Slam", "A heavy melee blow at up to 50 units that stuns for 0.5 seconds, cancelling whatever the target was casting.", CG.DamageType.PHYSICAL, 50.0, 16, 18, 2.0, 0, CG.Status.STUN, 8),

		## The Stalker's whole arsenal. MARKED for 6 seconds at 220 units,
		## with a projectile so it is a thing in flight the player can watch
		## rather than a status that appears from nowhere.
		##
		## 4/5 ticks of wind-up and recovery is the fastest cadence in the
		## bestiary, because a marker that has to survive a cast is a marker
		## that never marks anything: this enemy has 30 hp.
		##
		## **The 60-tick cooldown is a legibility fix and I measured the
		## problem before writing it.** `core_actions.gd`'s `_action_status`
		## hardcodes `cooldown_ticks` to 0, so the first cut of this fired
		## every 9 ticks against a 90-tick mark -- **229 applications across 20
		## fights, eleven per fight from one enemy**, each one emitting its own
		## `STATUS_APPLIED` and its own "is afflicted with Marked" line in the
		## combat log. Against the player's stated finish line, *"watch a fight
		## without pausing and broadly follow what happened and why"*, eleven
		## identical lines from a single 30hp enemy is the warning-becomes-
		## furniture failure: the player learns to skip Marked, and the one
		## application that mattered goes past unread.
		##
		## 60 rather than 90 so a Stalker that keeps line of sight can still
		## keep a target marked without a gap, which is the behaviour the enemy
		## is for. This moves numbers and I am reporting the movement rather
		## than choosing the cooldown to hit one.
		_projectile(_action_status_cd(&"stalker_mark", "Mark", "Marks a target within 220 units for 6 seconds, stripping its natural armour.", CG.DamageType.PHYSICAL, 220.0, 4, 5, 1.0, 0, CG.Status.MARKED, 90, 60, true), RANGED_PROJECTILE_SPEED),

		## **The Stalker's second action exists because the cooldown above
		## needs it to, and I found that by running it rather than by reading
		## it.** `DefaultBehavior.decide` builds its candidate list from
		## `_usable_actions` and returns `Intent.idle()` when that list is
		## empty, so a one-action enemy whose only action is on cooldown does
		## not kite, does not reposition and does not retreat -- it stands
		## still. Putting a 60-tick cooldown on a lone action would have made
		## this enemy inert for five sixths of every fight, which is a worse
		## outcome than the log spam the cooldown fixes.
		##
		## **THE ROTATION DOES NOT WORK AND THIS ACTION HAS NEVER FIRED. My
		## claim, measured false.** It used to read: "the rotation works the way
		## The Warden's does, through list order: `_choose_attack_action` finds
		## no melee action here, falls back to `_first_non_heal` over the
		## *usable* candidates, and `stalker_mark` is first -- so the Stalker
		## marks whenever it can and plinks with this the rest of the time."
		##
		## Counted with `Tools/SwarmProbe.gd` over 300 fights, every room, all
		## five buildable parties: `stalker_mark` fires 0.19 times per 100
		## ticks and **`stalker_dart` fires zero times, ever.**
		##
		## The word *usable* is what is wrong. `DefaultBehavior._usable_actions`
		## returns every action on the unit and filters neither cooldown nor
		## resource cost, so `stalker_mark` is chosen on every tick including
		## the 60 it is on cooldown for. `CombatSim._start_action` then refuses
		## it at the cooldown gate and **the tick is spent**. The dart under it
		## is never consulted.
		##
		## That is issue 22's fall-through bug exactly, on the enemy side of the
		## game, and it is the same first-affordable-action trap that kept
		## `warden_chain_toss` from ever firing -- which the paragraph below
		## warns about and which I then walked into anyway. Reported to rook:
		## the fix is one filter in `DefaultBehavior`, which is not my file.
		##
		## 200 units rather than 220 on purpose, so the dart never reaches
		## something the mark could not: an enemy that plinks at a range it
		## cannot mark at would spend the fight out of position for its own
		## specialty.
		_projectile(_action(&"stalker_dart", "Dart", "A light ranged dart at up to 200 units.", CG.DamageType.PHYSICAL, 200.0, 6, 8, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),

		## **Issue #130's BLEED source, and the fastest action in the game.**
		## 3 ticks of wind-up and 4 of recovery is a bite every 7 ticks, under
		## half the Goblin's 12. The player asked for *"something small that
		## hits fast"* and for a status that *"does damage less often but
		## stacks infinitely"* -- so the enemy is the delivery rate and the
		## status is the payload, and neither is dangerous alone.
		##
		## **A stack is worth more than the bite that carries it, and that is
		## the whole design.** At the live placeholders in `SimDeps` -- 1 per
		## stack per tick on a 5-tick rhythm -- one stack is 3 damage a second
		## against a 3-damage bite landing every half second, so a rat that
		## keeps biting overtakes its own direct damage inside two seconds and
		## keeps going. Four rats on one pawn is the shape #130 is about.
		##
		## **45 ticks of duration against a 30-tick per-stack decay, both
		## deliberate.** `CombatSim._tick_statuses` drops one stack on expiry
		## and re-arms for the decay window, so a pawn that breaks away from a
		## rat reads down 3, 2, 1, gone over about six seconds rather than
		## having nine stacks vanish on one tick. 45 is longer than the decay
		## so a bite always extends the bleed it lands on; shorter than twice
		## it so walking away is a real escape rather than a formality.
		##
		## power_scale 1.0 on `attack_power` 3. There is no hidden multiplier
		## here: the bite is meant to be beneath notice.
		_action_status(&"rat_bite", "Bite", "A fast melee bite at up to 40 units that adds a stack of Bleed.", CG.DamageType.PHYSICAL, 40.0, 3, 4, 1.0, 0, CG.Status.BLEED, 45),

		## **Floor 1's miniboss, and README wrote its whole design in one line:**
		## *"Big collection of rats joined at the tail. Ranged attacker, all
		## attacks leave behind rats which are close range melee attackers."*
		##
		## So this is one action doing two things, and that is the point rather
		## than a shortcut. Every other summon in the game is a dedicated
		## build action that deals nothing (`build_siege_engine`,
		## `power_scale` 0.0); this one damages **and** spawns, because "all
		## attacks leave behind rats" is not a summoning ability the king
		## chooses to use, it is what its attacks are. A separate summon action
		## would also have to win `DefaultBehavior`'s first-usable-action race
		## against the attack, which is the trap that kept `warden_chain_toss`
		## from ever firing.
		##
		## Ranged at 200 to match the goblin archer, so the king holds the
		## back rank and the rats it sheds do the closing -- the shape the
		## README line describes. 20/22 ticks is the slowest cadence in the
		## bestiary after the Brute: the swarm is the threat and the lash is
		## how the swarm arrives, so a fast lash would be two threats.
		##
		## **`max_active_summons` IS DELIBERATELY NOT SET, and I set it to 6
		## first and took it out.** The cap is enforced in
		## `PlanInterpreter._summon_slot_free`; enemies have no plans and go
		## through `DefaultBehavior`, whose `_usable_actions` returns every
		## action on the unit with no summon-slot check at all. **So a cap on
		## an enemy's summon does nothing whatever.**
		##
		## Two reasons it is out rather than set as documentation. It would be
		## a number a reader trusts and the simulation ignores, which is worse
		## than an absent one. And `test_content_siege_artillery.gd` asserts
		## that exactly one action in the game carries a cap -- that guard is
		## right, it is there to catch a cap set without thinking, and it
		## caught mine. I did not touch it.
		##
		## **It also turned out not to matter, which I measured rather than
		## assumed.** The uncapped swarm never exceeds the four rats the room
		## starts with, on any party, on any seed. That observation stands.
		##
		## **THE CAUSE I GAVE FOR IT WAS WRONG, and the real one is a defect
		## rather than a number.** This comment used to say "a 20 hp rat dies
		## faster than a 42-tick lash cycle replaces it", which reads as a
		## balance statement about the rat. Measured with `Tools/SwarmProbe.gd`,
		## 12 seeds x 5 buildable parties, counting every tick:
		##
		##   the lash fires a median of 1 time in a whole fight of ~250 ticks
		##   a fight of 250 ticks affords 6 lash cycles
		##   one party in five fires it ZERO times
		##   median rat lifetime is 60-96 ticks, which is not short
		##
		## The rat is not dying too fast. **The king is almost never allowed to
		## lash.** `DefaultBehavior` gives a ranged unit a firing band between
		## `range * KITE_RANGE_FRACTION` (0.6) and `range * RANGED_COMMIT_FRACTION`
		## (0.85) -- for a 200-range lash that is the 50 units between 120 and
		## 170. Inside 120 it retreats, beyond 170 it approaches. The king spends
		## **3-6% of its life inside that band**, 32-52% retreating and 43-59%
		## walking forward, and it walks on essentially every tick it is alive.
		##
		## It is not a general ranged defect: `goblin_arrow` has the same 200
		## range and fires 5.72 times per 100 ticks against this lash's 0.10,
		## because a Goblin Archer at move_speed 3.2 can re-establish the band
		## and the king at **1.2, the slowest unit in the game**, cannot. A
		## melee pawn closes on it once and it reverses for the rest of the
		## fight.
		##
		## So the swarm is dead for the reason CLAUDE.md's pawn-behaviour
		## principle names -- an automatic kiting branch the player cannot see
		## or edit, the same one that made the Abomination run away. Issue #97.
		## **Not tuned here.** No number in this file fixes a band that is a
		## fraction of whatever number I write, and raising the range widens the
		## band it cannot stay inside. Reported to rook with the table.
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

		## **Issue #121, the player's "big heavy guy that stuns units and
		## taunts". It stuns. It does not taunt, and the reason is a gap in
		## `Scripts/Plans/DefaultBehavior.gd`, not a decision of mine.**
		##
		## A self-buff is unreachable to any enemy in this game. `decide()`
		## always picks a target from the *opposing* team and then compares
		## `dist` against the chosen action's `range_units`, so a
		## self-targeted action at range 0.0 makes its owner walk toward a foe
		## forever and never fire -- there is no self-target branch, and
		## `PlanInterpreter`'s `target_self` is the only thing in the game
		## that provides one. Aiming a taunt at a foe instead is worse than
		## useless: `_apply_action_effect` applies the status to the *target*,
		## so a `brute_roar` pointed at a pawn would make the Brute's allies
		## pile onto that pawn, which is a focus-fire mechanic wearing a
		## taunt's name.
		##
		## `EnemyDef.spawn_taunt_radius` is the one existing way an enemy can
		## taunt, and I deliberately did not use it. It applies TAUNTING at
		## `CG.MAX_TICKS`, an aura that outlives the fight, and a pawn inside
		## it is forced to select the Brute and then forced to approach it
		## every tick after. That is precisely the *permanent lock* the
		## player's #58 ruling forbids ("taunts must not permanently lock a
		## pawn"), and reaching for it would have shipped the letter of the
		## ask against the ruling that governs it.
		##
		## So the Brute ships as a heavy with a stun, `brute_roar` is not in
		## this file at all rather than sitting here unreachable, and the
		## finite-duration taunt is one branch in a file that is not mine.
		## Reported on the board with the exact shape.
		##
		## Numbers: hp 320 is second only to The Warden and 1.6x the Ghoul,
		## move_speed 1.8 is the second slowest thing that moves, and
		## `damage_reduction` 0.15 is the highest in the bestiary. Issue 12's
		## rule that any two enemies differ by 2x on some axis holds against
		## every one of them -- against the Ghoul, its nearest neighbour, hp
		## is 320 vs 200 and reduction 0.15 vs 0.10, but `brute_slam`'s
		## power_scale 2.0 against 24 base is 48 to the Ghoul's 20, which is
		## 2.4x.
		##
		## focus_bias 0.0: a Brute walks at whoever is closest and does not
		## care what its allies are doing. A slow enemy that piles onto a
		## distant target spends the fight walking.
		_enemy(&"brute", "Brute", 320, 0, CG.ResourceKind.ENERGY, 1.8, 18.0, {CG.DamageType.PHYSICAL: 24}, 0.15, [&"brute_slam"], ["Melee", "Tough", "Stun"], 0.0),

		## **Issue #121's anti-support specialist. Deliberately fragile at 30
		## hp, and my own comment here was wrong when I wrote it** -- it said
		## "the squishiest thing in the game, under the Goblin Archer's 28 by
		## two", and 30 is above 28, not under it. The Goblin Archer was
		## already the squishiest thing in the game and still is until the Rat
		## below at 20. Corrected rather than quietly dropped: it was the kind
		## of claim a reader would take on trust and nothing would ever check.
		## It deals 5 damage. It is a threat because of what it
		## enables, not what it deals, and I would rather ship it visibly weak
		## and say so than pad its damage until it looks useful.
		##
		## **What its mark actually does today, measured rather than assumed,
		## because half of it is missing.** MARKED subtracts
		## `Balance.MARKED_VULNERABILITY_BONUS` (0.25) from the target's
		## damage reduction, so against a pawn it strips all of that pawn's
		## CON-derived natural armour -- real, and small, and it will get much
		## larger the day #100 lets a pawn wear plate. What does *not* exist is
		## the half the player actually asked for: *"it just causes ranged
		## enemies to focus their fire on a specific target."* Enemy target
		## selection has a marked-only **restriction**
		## (`_all_attacks_require_a_mark`, generic on both teams) and no
		## marked **preference**, so the Goblin Archers standing beside this
		## thing still shoot whoever is nearest. That tie-break is one filter
		## in `DefaultBehavior._choose_target` and it is not my file.
		##
		## focus_bias 0.5 is set for the day that lands, and does nothing
		## interesting until then: this enemy has one action and it is the
		## mark.
		_enemy(&"stalker", "Stalker", 30, 0, CG.ResourceKind.ENERGY, 3.8, 10.0, {CG.DamageType.PHYSICAL: 5}, 0.0, [&"stalker_mark", &"stalker_dart"], ["Ranged", "Weak", "Support"], 0.5),

		## **Issue #130's BLEED source. The player's words are "something small
		## that hits fast", and every number here is that sentence and nothing
		## else.**
		##
		## 20 hp, the least in the game, below the Goblin Archer's 28.
		## move_speed 5.0, the most in the game, above the Goblin's 4.0.
		## 3 damage a bite, the least in the game. `radius` 8.0, the smallest
		## body in the game. **A rat loses every exchange it is in.** What it
		## has instead is `rat_bite`'s 7-tick cycle and a status that does not
		## reset.
		##
		## **A rat rather than an invention, and the art was already there.**
		## `Silhouettes.gd` has carried a `rat` shape in `UNUSED_SHAPES` since
		## before any content existed, and README's floor-1 miniboss is the Rat
		## King -- *"all attacks leave behind rats which are close range melee
		## attackers"* -- so this is the thing that miniboss is made of rather
		## than a one-off. That is the second time sable's ahead-of-content art
		## has met the content it was drawn for, after the Brute.
		##
		## focus_bias 0.8, the highest in the game, above the Goblin's 0.7.
		## This is the one number that is about the status rather than about
		## the body: BLEED is the first thing in this game where **hitting the
		## same target twice is worth more than hitting two targets once**, so
		## a swarm that splits its bites across four pawns wastes the mechanic
		## it exists to carry. A high bias is what makes a rat pack read as a
		## pack.
		##
		## Issue 12's rule that any two enemies differ by 2x on some axis: hp
		## 20 against the Goblin's 35 is 1.75x, but damage 3 against 9 is 3x
		## and against the Brute's 24 is 8x.
		_enemy(&"rat", "Rat", 20, 0, CG.ResourceKind.ENERGY, 5.0, 8.0, {CG.DamageType.PHYSICAL: 3}, 0.0, [&"rat_bite"], ["Melee", "Weak", "Bleed"], 0.8),

		## **Floor 1's miniboss. README pairs it with The Warden, and it is the
		## opposite kind of fight in every way I could make it.**
		##
		## The Warden is one body with 1000 hp that walks at you. The Rat King
		## is 420 hp that never closes and keeps making the problem wider. A
		## party that beats the Warden by out-damaging one target has to do
		## something different here, which is the only reason to have two
		## minibosses on one floor.
		##
		## move_speed 1.2 -- slower than anything else that moves, slower than
		## the Warden's 1.4. A thing made of rats joined at the tail should not
		## be nimble, and mechanically it is what stops the king closing: it
		## sheds rats and they arrive, it does not.
		##
		## `damage_reduction` 0.0 on purpose, against the Warden's 0.05 and the
		## Brute's 0.15. It has no armour at all -- it is a knot of small
		## animals. What protects it is the distance and the bodies in front of
		## it, and if a party gets to it, it should die like the thing it is
		## made of.
		##
		## focus_bias 0.0: the king picks the nearest and does not join a pile.
		## Its rats carry 0.8 and swarm, which is the division of labour the
		## README line implies.
		##
		## **21 damage on a 42-tick cycle is 7.5 a second, less than half the
		## Warden's axe.** Direct damage is not what this fight is; if the king
		## out-damaged its own swarm the swarm would be scenery.
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
