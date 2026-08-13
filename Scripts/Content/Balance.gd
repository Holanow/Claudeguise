extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")

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
const BURN_DAMAGE_PERCENT_PER_TICK := 0.5
const POISON_DAMAGE_PERCENT_PER_TICK := 0.30

## Issue 23: multiplier on wind-up/recovery ticks while HASTE is active.
## Below 1.0 speeds a unit up; wren's simulation floors the result at one
## tick, so this cannot make an action instant by accident.
const HASTE_TICK_SCALE := 0.7

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

## Fraction of incoming damage removed, from armor and statuses. The simulation
## applies this; it does not decide it.
static func damage_reduction(unit: CombatUnit) -> float:
	if unit.pawn == null:
		return 0.0
	var reduction := clampf(attribute(unit.pawn, CG.Attribute.CON) * DAMAGE_REDUCTION_PER_CON, 0.0, NATURAL_DAMAGE_REDUCTION_CAP)
	if unit.pawn.armor != null:
		reduction += unit.pawn.armor.damage_reduction
	if unit.has_status(CG.Status.SHIELD):
		reduction += STATUS_SHIELD_REDUCTION
	if unit.has_status(CG.Status.BLOCK):
		reduction += STATUS_BLOCK_REDUCTION
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
		CG.Status.BURN:
			return float(unit.hp_max) * (BURN_DAMAGE_PERCENT_PER_TICK / 100.0)
		CG.Status.POISON:
			return float(unit.hp_max) * (POISON_DAMAGE_PERCENT_PER_TICK / 100.0)
	return 0.0

## Multiplier on wind-up/recovery ticks for a unit carrying HASTE. `unit` is
## accepted for the call shape SimDeps expects; the multiplier itself is flat
## across every unit for this slice, same as attack variance was before it
## needed a per-class knob.
static func haste_tick_scale(unit: CombatUnit) -> float:
	var _unused := unit
	return HASTE_TICK_SCALE

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
## Issue 13: halved from 0.20/0.30. The original pair, measured with
## `Tools/FloorRuns.gd` once the call site existed (#11), cleared every
## leave-one-out party 20/20 including `no_siege_master`, which cleared
## 5/20 unaided -- the floor had stopped grinding anyone down at all.
##
## The response to these two constants is a step function, not a slope:
## `no_siege_master`'s 20-seed clear count sits at 5/20 for any pair below
## roughly 0.069/0.119 and jumps straight to 19/20 for nearly everything
## above it, all the way up past this pair to the original 0.15/0.20 --
## one seed's outcome never moved across that whole range. There is no
## smooth value that lands it at, say, 12/20; the seeds share enough
## structure that most of them cross their own win/loss line at once. This
## pair sits inside that 19/20 plateau rather than on either edge, which
## is the most stable answer available from this lever alone: entering the
## last room measured 78-87% across every party (was 84-93%), and only
## `no_siege_master` fails to clear -- once, not always.
const BASE_RECOVERY_FRACTION := 0.10
const HEALER_RECOVERY_BONUS := 0.15

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
