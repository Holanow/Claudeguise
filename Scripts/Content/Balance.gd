extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")

## Every tuning number in the game and every formula that turns attributes into
## the values the simulation uses.
##
## OWNER: teal.
##
## This file exists as a separate thing on purpose. The question this slice
## answers is whether the combat is fun, and answering it means changing numbers
## and re-running the same fight. If the numbers are spread through the
## simulation then every tuning pass is a diff in wren's files and a merge
## conflict. Here it is one file, one owner, one place to look.
##
## The simulation calls these. It must never hardcode a number that belongs
## here, and a reviewer should reject one that does.

const BASE_HP := 60
const HP_PER_CON := 12
const HP_PER_STR_BONUS := 2

const BASE_RESOURCE := 30
const RESOURCE_PER_ATN := 8
const RESOURCE_PER_INT_BONUS := 2

## World units per tick.
const BASE_MOVE_SPEED := 3.0
const MOVE_PER_AGI := 0.4
const MOVE_PER_DEX_BONUS := 0.05

const ATTACK_POWER_PER_POINT := 1.9

## Issue 7: a hit rolls within [1 - spread, 1 + spread] of its base power.
## Drawn from the fight's own `CombatState.rng`, never a fresh generator, so
## the same seed still reproduces the same fight exactly. 0.0 disables
## variance entirely, which is what every caller gets by not passing `rng`.
const ATTACK_VARIANCE_SPREAD := 0.55

const DAMAGE_REDUCTION_PER_CON := 0.01
const NATURAL_DAMAGE_REDUCTION_CAP := 0.3
const STATUS_SHIELD_REDUCTION := 0.25
const STATUS_BLOCK_REDUCTION := 0.25
const MAX_DAMAGE_REDUCTION := 0.85

## Fraction shaved off an action's ticks per point of AGI, capped so a very
## fast pawn still takes at least half the base time.
const AGI_TICK_SCALE_PER_POINT := 0.015
const MAX_AGI_TICK_SCALE := 0.5

## Issue 20: percent of max resource per second. Mana large and slow, Energy
## small and fast, per README.md. Rage is never read here on a timer — wren's
## simulation already refuses to call this for a RAGE unit, and this function
## returns 0.0 for one anyway as a second guard.
const MANA_REGEN_PERCENT_PER_SECOND := 4.0
const ENERGY_REGEN_PERCENT_PER_SECOND := 18.0

## Issue 20: percent of max Rage gained per landed attack. README.md: Rage
## "fills as the pawn attacks" and nothing else — wren's simulation only calls
## this on a hit that actually lands, never on commit and never on a miss.
const RAGE_GAIN_PERCENT_PER_HIT := 18.0

## Issue 23: percent of the victim's own max hp lost per BURN/POISON tick.
## Proportional rather than flat so a Ghoul and a Goblin Archer find the same
## burn equally scary instead of it being trivial for one and lethal in three
## ticks for the other. Burn a touch hotter than poison, per README's own
## flavour text ("Fire: Enrage, Burn" reads more violent than a lingering
## "Water: Cleanse, Soak"-adjacent Profane poison).
## **BURN no longer has one, and its removal is half of issue 121's BURN work.**
## The player's rule is *"BURN damage per tick should be relative to the hit that
## applied it"*, which is `BURN_FRACTION_OF_HIT_PER_TICK` below. swift's seam adds
## the two terms together, so leaving a percent-of-max-health rate here would make
## burn do both at once -- a fixed rate for being on fire plus a rate for the hit.
## The two are alternative answers to the same question and only one is the
## player's.
const POISON_DAMAGE_PERCENT_PER_TICK := 0.30

## **BURN, and this is the number the whole mechanism turns on.** Fraction of the
## applying hit's *mitigated* damage that burn deals **per tick**, multiplied by
## `CombatUnit.status_magnitude[BURN]`, which `CombatSim` stores as exactly that
## damage.
##
## **Per tick is the trap, and swift flagged it in advance: the honest denominator
## is the duration, not the fraction that looks small.** 0.2 here on a 90-tick
## burn would return eighteen times the original hit. So this is derived from the
## total, backwards:
##
##     total = BURN_FRACTION_OF_HIT_PER_TICK * duration
##     0.0056 * 90 ticks = 0.5
##
## **A burn left alone deals about half the hit that lit it, over six seconds.**
## That is the ratio the number comes from, not a win rate -- burn is worth
## noticing and is never a second hit. `BURN_DURATION_TICKS` in `core_actions.gd`
## is the other half of the pair and the two must move together; there is a test
## asserting the product rather than either number, so changing one alone fails.
const BURN_FRACTION_OF_HIT_PER_TICK := 0.0056

## **BLEED is issue 130's, not this issue's, and this value is swift's live
## placeholder copied across unchanged (`SimDeps._BLEED_DAMAGE_PER_STACK_PER_TICK`
## = 1.0).** It is here only so that repointing `SimDeps` at `Balance` cannot move
## a number on the way past. Nothing in the game applies BLEED, so it is inert
## either way -- but a rate feeds `_stochastic_round`, which draws from the
## fight's shared rng, so a rate that moved by any amount at all would change the
## outcome of every fight in the game rather than only the bleeding ones. That is
## swift's own reasoning and it is why this is a copy rather than a fresh guess.
const BLEED_DAMAGE_PER_STACK_PER_TICK := 1.0

## Issue 23: multiplier on wind-up/recovery ticks while HASTE is active.
## Below 1.0 speeds a unit up; wren's simulation floors the result at one
## tick, so this cannot make an action instant by accident.
const HASTE_TICK_SCALE := 0.7

## Issue 52: multiplier on move_speed while SLOWED is active. `SimDeps` ran
## on a local placeholder of the same value (0.5) until this landed --
## `_default_slowed_speed_scale`'s own doc comment names this exact function
## as the thing it is waiting on. Half speed: enough that a hooked target
## cannot simply walk back out of `abomination_grapple`'s own melee range
## before the Abomination's next action is ready, not so little that SLOWED
## reads as a second STUN (STUN is the full lockout; this is a unit still
## fighting, just unable to leave, per CG.Status.SLOWED's own doc comment).
const SLOWED_SPEED_SCALE := 0.5

## Issue 39: an attribute including equipment's `attribute_flat` and
## `attribute_percent` (weapons and accessories: percent per README.md; armor:
## flat, plus occasional percent on CON). The single place a stat multiplier
## is applied, per the item system's own design note -- every formula below
## reads a stat through here rather than through `pawn.attribute()` directly,
## so equipment cannot be double-counted by one caller and skipped by
## another. `pawn.attribute()` itself (Core) stays base-class-plus-manual-
## bonus only and equipment layers on top of it here.
static func attribute(pawn: PawnData, a: CG.Attribute) -> float:
	var value := float(pawn.attribute(a))
	var flat := 0.0
	var percent := 0.0
	for e in pawn.equipment():
		flat += float(e.attribute_flat.get(a, 0))
		percent += float(e.attribute_percent.get(a, 0.0))
	return (value + flat) * (1.0 + percent)

static func max_hp(pawn: PawnData) -> int:
	var str_bonus := attribute(pawn, CG.Attribute.STR)
	return int(round(BASE_HP + attribute(pawn, CG.Attribute.CON) * HP_PER_CON + str_bonus * HP_PER_STR_BONUS))

static func max_resource(pawn: PawnData) -> int:
	var int_bonus := attribute(pawn, CG.Attribute.INT)
	return int(round(BASE_RESOURCE + attribute(pawn, CG.Attribute.ATN) * RESOURCE_PER_ATN + int_bonus * RESOURCE_PER_INT_BONUS))

## World units per tick.
static func move_speed(pawn: PawnData) -> float:
	var dex_bonus := attribute(pawn, CG.Attribute.DEX)
	return BASE_MOVE_SPEED + attribute(pawn, CG.Attribute.AGI) * MOVE_PER_AGI + dex_bonus * MOVE_PER_DEX_BONUS

## Attack power for one damage type, before the action's own power_scale.
##
## Per README.md: Martial+Melee scales off STR, Martial+Ranged (and
## Martial+Summoner, which has no dedicated attribute) scales off DEX, and any
## Magical class scales off INT regardless of style. `d` is accepted for the
## call shape SimDeps expects; the driving attribute for this slice comes from
## the class's method and style, not from the damage type of the action fired.
##
## `rng` is optional and defaults to null, which returns the flat, no-variance
## number every existing caller got before issue 7 — widening this signature
## cannot break anything that does not opt in. Pass the fight's own
## `CombatState.rng` to get a varied roll; passing a fresh generator instead
## would break "same seed, same fight" and must never happen.
static func attack_power(pawn: PawnData, d: CG.DamageType, rng: RandomNumberGenerator = null) -> float:
	var _unused := d
	if pawn.pawn_class == null:
		return 0.0
	var attr := CG.Attribute.STR
	if pawn.pawn_class.method == CG.Method.MAGICAL:
		attr = CG.Attribute.INT
	elif pawn.pawn_class.style == CG.Style.MELEE:
		attr = CG.Attribute.STR
	else:
		attr = CG.Attribute.DEX
	var base := attribute(pawn, attr) * ATTACK_POWER_PER_POINT
	if rng == null:
		return base
	return base * rng.randf_range(1.0 - ATTACK_VARIANCE_SPREAD, 1.0 + ATTACK_VARIANCE_SPREAD)

## Issue 12: how much extra damage a MARKED unit takes. Subtracted from
## reduction rather than added as a separate multiplier, so a heavily
## armoured target reads as "the mark burned through some of that armour"
## and a bare one reads as "already exposed, now more so" -- one number,
## one mental model. Large enough on an enemy with 0.0 base reduction
## (every enemy but The Warden) to be the whole point of bringing a
## Spotter: measurably increases damage taken is issue 12's own criterion 4.
const MARKED_VULNERABILITY_BONUS := 0.25

## Fraction of incoming damage removed, from armor, natural toughness and
## statuses. The simulation applies this; it does not decide it.
##
## Issue 12: previously returned 0.0 outright for any unit without a
## `pawn` -- every enemy in the game -- because `SimDeps` read
## `EnemyDef.damage_reduction` directly instead of calling this at all.
## That meant MARKED, applied to an enemy, could never do anything: the
## status lives on `CombatUnit`, which enemies have, but the number it
## should adjust was never read through the function that checks statuses.
## Enemies now flow through here too, so the one place a status changes
## incoming damage is really the only place, for both sides of a fight --
## same reasoning as `attribute()` centralising equipment for issue 39.
static func damage_reduction(unit: CombatUnit) -> float:
	var reduction := 0.0
	if unit.pawn != null:
		reduction = clampf(attribute(unit.pawn, CG.Attribute.CON) * DAMAGE_REDUCTION_PER_CON, 0.0, NATURAL_DAMAGE_REDUCTION_CAP)
		if unit.pawn.armor != null:
			reduction += unit.pawn.armor.damage_reduction
	else:
		var enemy_def: EnemyDef = Registry.get_enemy(unit.enemy_id)
		if enemy_def != null:
			reduction = enemy_def.damage_reduction
	if unit.has_status(CG.Status.SHIELD):
		reduction += STATUS_SHIELD_REDUCTION
	if unit.has_status(CG.Status.BLOCK):
		reduction += STATUS_BLOCK_REDUCTION
	if unit.has_status(CG.Status.MARKED):
		reduction -= MARKED_VULNERABILITY_BONUS
	return clampf(reduction, 0.0, MAX_DAMAGE_REDUCTION)

## How many blocks a pawn's plans may total, from WIS per README.md.
static func plan_block_budget(pawn: PawnData) -> int:
	return maxi(1, pawn.attribute(CG.Attribute.WIS))

## Ticks a wind-up or recovery takes after AGI is applied. Kept as a modifier on
## the action's own numbers so that "this action is slow" and "this pawn is
## slow" stay separately readable.
static func scale_action_ticks(base_ticks: int, pawn: PawnData) -> int:
	if base_ticks <= 0:
		return base_ticks
	var scale := clampf(attribute(pawn, CG.Attribute.AGI) * AGI_TICK_SCALE_PER_POINT, 0.0, MAX_AGI_TICK_SCALE)
	return maxi(1, int(round(float(base_ticks) * (1.0 - scale))))

## What a pawn's resource pool holds at the moment a fight starts.
##
## Issue 132, the player's own words: *"Resource should return to some kind of
## default state per room, mana would be full while energy and rage would be 0."*
##
## **Scope, because the issue names a tension and it is easy to overshoot:** "per
## room" is a run concept and runs are parked, so this is the state a *fight*
## starts in and nothing about carrying anything between rooms. rook confirmed.
##
## **Pawns only. Enemies keep full pools** and `CombatSim` calls this on the pawn
## branch alone -- rook's ruling on my question. The player's paragraph is about
## mana classes, their default attacks and a mana-restoring ability; nothing in it
## is about goblins, and changing the enemy branch because it happens to be the
## same line would move every measurement in the project a second time in a week.
##
## The asymmetry it creates is deliberate: Rage and Energy are meant to be
## *earned* within a fight, which is what makes a free basic attack the thing that
## funds a finisher (issue 129) rather than a fallback nobody needs. Mana is full
## because a caster that cannot cast on tick one is not playing the first half of
## the fight -- the exact defect issue 62 fixed once already.
static func starting_resource(kind: CG.ResourceKind, max_resource: int) -> int:
	match kind:
		CG.ResourceKind.MANA:
			return max_resource
		CG.ResourceKind.ENERGY, CG.ResourceKind.RAGE:
			return 0
	return max_resource

## Resource regenerated per tick, before rounding. Rage returns 0.0: it never
## rises on a timer, only from rage_gain_per_attack.
static func resource_regen_per_tick(unit: CombatUnit) -> float:
	var percent_per_second := 0.0
	match unit.resource_kind:
		CG.ResourceKind.MANA:
			percent_per_second = MANA_REGEN_PERCENT_PER_SECOND
		CG.ResourceKind.ENERGY:
			percent_per_second = ENERGY_REGEN_PERCENT_PER_SECOND
		CG.ResourceKind.RAGE:
			return 0.0
	return float(unit.resource_max) * (percent_per_second / 100.0) / float(CG.TICKS_PER_SECOND)

## Rage gained the moment an attack lands. 0.0 for any other resource kind:
## Mana and Energy regenerate on a timer instead, never from landing a hit.
static func rage_gain_per_attack(unit: CombatUnit) -> float:
	if unit.resource_kind != CG.ResourceKind.RAGE:
		return 0.0
	return float(unit.resource_max) * (RAGE_GAIN_PERCENT_PER_HIT / 100.0)

## Damage dealt by one BURN or POISON tick. 0.0 for any other status -- wren's
## simulation only calls this for those two, but a wrong status reaching here
## should read as "does nothing" rather than an error over something display-
## only would never notice.
static func status_damage_per_tick(unit: CombatUnit, status: CG.Status) -> float:
	match status:
		CG.Status.POISON:
			return float(unit.hp_max) * (POISON_DAMAGE_PERCENT_PER_TICK / 100.0)
	return 0.0

## Damage per tick contributed by each unit of a status's stored magnitude, on
## top of `status_damage_per_tick`. swift's seam; see `SimDeps` for the whole
## expression and for why the two terms exist.
##
## **BURN only.** POISON stores no magnitude so this term is already zero for it,
## and BLEED is issue 130's -- **it returns swift's live placeholder value
## unchanged here rather than 0.0, deliberately.** Repointing `SimDeps` at this
## function must not change a number on the way past: nothing in the game applies
## BLEED today, so the value is inert either way, but "inert" is not a reason to
## let a rate silently move. When #130 authors bleed for real, this is where its
## number belongs.
static func status_damage_per_magnitude(unit: CombatUnit, status: CG.Status) -> float:
	var _unused := unit
	match status:
		CG.Status.BURN:
			return BURN_FRACTION_OF_HIT_PER_TICK
		CG.Status.BLEED:
			return BLEED_DAMAGE_PER_STACK_PER_TICK
	return 0.0

## Multiplier on wind-up/recovery ticks for a unit carrying HASTE. `unit` is
## accepted for the call shape SimDeps expects; the multiplier itself is flat
## across every unit for this slice, same as attack variance was before it
## needed a per-class knob.
static func haste_tick_scale(unit: CombatUnit) -> float:
	var _unused := unit
	return HASTE_TICK_SCALE

## Multiplier on move_speed for a unit carrying SLOWED. `unit` is accepted
## for the call shape SimDeps expects (same reasoning as haste_tick_scale
## above); the multiplier is flat across every unit for this slice.
static func slowed_speed_scale(unit: CombatUnit) -> float:
	var _unused := unit
	return SLOWED_SPEED_SCALE

## Issue 45: how much health a run restores between rooms, and the answer is
## "some, and more if the party brought a Healer" -- README's own text for
## the role ("meant to restore health and revive allies") is the most
## directly supported reading of the four candidates the issue named, and it
## is the only one that does not need a new `FloorRoom.Type` (wren's shape)
## to exist before it can do anything.
##
## Deliberately NOT full recovery. `FloorRun` carries damage forward on
## purpose -- issue 41 and 37's whole finding was that a room should cost
## something -- and healing every pawn back to 100% between every room
## would undo that the same way starting weapons did. This restores a
## fraction of what is *missing*, not a fraction of max: a party that
## finished a room at 23% recovers meaningfully without being handed back
## the fight-ending margin a full heal would give the next room for free.
##
## BASE_RECOVERY covers "the party rests" on its own -- bandages, water, a
## few minutes off their feet, nothing that needs a class for. HEALER_BONUS
## is additive on top when a HEALER-role class survived the room: the
## Healer's whole distinguishing value per README should be visible between
## fights, not only inside one.
##
## Issue 13's history, kept because it explains why the shape below is the
## simple one and not one of the fancier ones tried along the way:
##
## First pass halved these from 0.20/0.30 to 0.10/0.15. `no_siege_master`
## moved from 20/20 to 19/20 -- an improvement, but the issue wanted it
## somewhere between 5/20 (unaided) and 20/20, not sitting one seed under
## the ceiling.
##
## Second pass tried reshaping instead of rescaling: a flat cap on the
## amount handed back per room, then recovery multiplied by the party's own
## current health fraction (a real feedback loop -- worse-off recovers
## proportionally less), then that same idea cubed for a sharper penalty.
## All three, like the original pair, were swept fine enough to find a
## middle value if one existed. None did. Every shape landed
## `no_siege_master` on exactly 5/20 or 19/20 and never between, which is
## proof rather than bad luck: no function of `(hp, hp_max,
## has_living_healer)` can move that specific row, because a cluster of this
## floor's seeds is decided by one pivotal fight the Siege Master's own
## near-mandatory range advantage governs (issue 4), not by how generously
## the party is patched up between rooms. Recovery was never the right lever
## for that number.
##
## rook's call once that was shown: criterion 2 comes out of issue 13 and
## goes to issues 4/12/14, which fix the Siege Master's actual power gap
## directly. Recovery keeps one job -- does the floor wear a party down --
## and gets judged on that alone, which is why this is back to the simplest
## shape (straight percent of what's missing) rather than any of the
## reshaped ones: a curve contorted to satisfy two criteria that pulled
## against each other was never going to read as clean attrition, and now
## it only has to satisfy one.
##
## Tuned against `Tools/FloorRuns.gd`: every party but `no_siege_master`
## (whose own number is no longer this issue's concern, see above) enters
## the boss room worn to roughly 79-85%, down from 84-93% and close to the
## 72-83% the floor produces with no recovery at all -- recovery is a real
## but modest cushion on top of the floor's own attrition, not a replacement
## for it, while every one of those four still clears 20/20. `no_priest` has
## no living Healer by construction (the class itself is missing) and
## recovers on `BASE_RECOVERY_FRACTION` alone; whether that reads lower than
## another party's own boss-entry number is confounded by the two parties
## being different pawns with different survivability, so it is not the
## proof the bonus matters -- `test_a_living_healer_recovers_more` is: same
## carried hp, same hp_max, and a living Healer recovers more, every time,
## by construction of the formula below rather than by which five seeds ran.
const BASE_RECOVERY_FRACTION := 0.04
const HEALER_RECOVERY_BONUS := 0.08

## `has_living_healer` is the caller's to determine (a run's own carried
## party state, read by whoever wires this in) -- this function does not
## know about FloorRun or which pawns are alive, on purpose, so it stays
## testable without either.
static func between_room_recovery_fraction(has_living_healer: bool) -> float:
	var fraction := BASE_RECOVERY_FRACTION
	if has_living_healer:
		fraction += HEALER_RECOVERY_BONUS
	return fraction

## Applies the fraction above to one pawn's carried hp. Missing health is
## `hp_max - hp`; this restores `recovery_fraction` of that gap, rounded, and
## never returns above `hp_max` or below the hp passed in (a pawn already at
## or above max is left alone rather than clamped down, since this is a
## recovery function and never a damage one).
static func between_room_heal(hp: int, hp_max: int, has_living_healer: bool) -> int:
	if hp >= hp_max:
		return hp
	var missing := hp_max - hp
	var recovered := int(round(float(missing) * between_room_recovery_fraction(has_living_healer)))
	return mini(hp_max, hp + recovered)

## README's other half of the Healer's stated purpose: "revive allies". A
## dead pawn currently stays dead for the rest of a run per issue 45's own
## finding -- against a floor that already grinds a party down, that reads
## as a death sentence rather than a setback. Only fires with a living
## Healer in the party; a dead pawn stays dead without one, which is the
## stakes issue 45 says a run should have. Revived at a fraction of max hp
## rather than full -- a revival is a second chance, not a free win back.
const REVIVE_HP_FRACTION := 0.35

static func revive_hp(hp_max: int, has_living_healer: bool) -> int:
	if not has_living_healer:
		return 0
	return int(round(float(hp_max) * REVIVE_HP_FRACTION))

## Found mid-#30, while measuring `no_warrior`'s own 0/20: `FloorRun` carries
## resource forward exactly, same as it did for hp before issue 45 --
## `Tools/FloorRuns.gd` (once it reported resource at all; it did not until
## rook added the column) shows every real party's resource crashing from
## 100% to 7-23% by the boss room, while hp only drifts to 71-84%. Health
## was never what wore a party down. Resource was, and nothing recovered it
## between rooms because nothing was asked to.
##
## Confirmed causally, not by correlation (swift): `no_warrior` (no Warrior
## at all, so its casters carry the floor) wins the Warden 18/20 fresh and
## loses 20/20 arriving worn -- same hp, different resource. That isolates
## the variable.
##
## Same shape as `between_room_heal` on purpose: a fraction of what is
## *missing*, not a full restore, for the same reason a full heal would
## have undone health's own attrition. No Healer-role bonus here --
## nothing in this class's kit right now restores an ally's resource, only
## its own hp (`priest_heal`), so a bonus keyed to "a Healer is alive"
## would reward a class for something it does not do. Tuned separately
## from `BASE_RECOVERY_FRACTION` above: resource and hp are different
## economies (resource already regenerates every tick in-fight, at
## MANA_REGEN_PERCENT_PER_SECOND / ENERGY_REGEN_PERCENT_PER_SECOND, on top
## of whatever this restores between rooms) and there is no reason to
## assume the same number solves both.
##
## Tuned against a probe replicating `Tools/FloorRuns.gd`'s own loop (the
## real wire into `FloorFightRunner.gd` isn't mine -- see the ask on the
## board) with this function's effect patched on top of what `play_room`
## already does for hp. Swept 0.20/0.35/0.45/0.50/0.65: `no_warrior` moved
## 0/20 -> 1/20 -> 5/20 -> 11/20 -> 11/20, non-monotonic between 0.45 and
## 0.50 the same way health's own recovery swept in steps rather than a
## smooth curve. Landed on 0.50, the value where it stopped being an
## outright trap without diminishing returns past it (0.65 bought nothing
## further). Every other real party stays 20/20 throughout the whole sweep;
## `no_abomination` stays 0/20 at every value -- expected, per swift's own
## finding that it loses the boss even fresh, a second, separate problem
## from attrition.
const BASE_RESOURCE_RECOVERY_FRACTION := 0.50

## Applies the fraction above to one pawn's carried resource. Missing
## resource is `resource_max - resource`; this restores
## `BASE_RESOURCE_RECOVERY_FRACTION` of that gap, rounded, and never returns
## above `resource_max` or below the resource passed in -- same clamping
## reasoning as `between_room_heal`: a pawn already full is left alone
## rather than clamped down, since this is a recovery function and never a
## drain one.
static func between_room_resource_recover(resource: int, resource_max: int) -> int:
	if resource >= resource_max:
		return resource
	var missing := resource_max - resource
	var recovered := int(round(float(missing) * BASE_RESOURCE_RECOVERY_FRACTION))
	return mini(resource_max, resource + recovered)
