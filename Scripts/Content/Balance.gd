extends RefCounted
class_name Balance


## Every tuning number in the game and every formula that turns attributes into
## the values the simulation uses.

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
## small and fast, per README.md. Rage is never read here on a timer Ã¢â‚¬-- wren's
## simulation already refuses to call this for a RAGE unit, and this function
## returns 0.0 for one anyway as a second guard.
const MANA_REGEN_PERCENT_PER_SECOND := 4.0
const ENERGY_REGEN_PERCENT_PER_SECOND := 18.0

## Issue 20: percent of max Rage gained per landed attack. README.md: Rage
## "fills as the pawn attacks" and nothing else Ã¢â‚¬-- wren's simulation only calls
## this on a hit that actually lands, never on commit and never on a miss.
const RAGE_GAIN_PERCENT_PER_HIT := 18.0

## Issue 23: percent of the victim's own max hp lost per BURN/POISON tick.
## Proportional rather than flat so a Ghoul and a Goblin Archer find the same
## burn equally scary instead of it being trivial for one and lethal in three
const POISON_DAMAGE_PERCENT_PER_TICK := 0.30

## **BURN, and this is the number the whole mechanism turns on.** Fraction of the
## applying hit's *mitigated* damage that burn deals **per tick**, multiplied by
## `CombatUnit.status_magnitude[BURN]`, which `CombatSim` stores as exactly that
const BURN_FRACTION_OF_HIT_PER_TICK := 0.0056

## **BLEED is issue 130's, not this issue's, and this value is swift's live
## placeholder copied across unchanged (`SimDeps._BLEED_DAMAGE_PER_STACK_PER_TICK`
## = 1.0).** It is here only so that repointing `SimDeps` at `Balance` cannot move
const BLEED_DAMAGE_PER_STACK_PER_TICK := 1.0

## Issue 23: multiplier on wind-up/recovery ticks while HASTE is active.
## Below 1.0 speeds a unit up; wren's simulation floors the result at one
## tick, so this cannot make an action instant by accident.
const HASTE_TICK_SCALE := 0.7

## Issue 52: multiplier on move_speed while SLOWED is active. `SimDeps` ran
## on a local placeholder of the same value (0.5) until this landed --
## `_default_slowed_speed_scale`'s own doc comment names this exact function
const SLOWED_SPEED_SCALE := 0.5

## Issue 39: an attribute including equipment's `attribute_flat` and
## `attribute_percent` (weapons and accessories: percent per README.md; armor:
## flat, plus occasional percent on CON). The single place a stat multiplier
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
##
## **Issue 269: through `attribute()`, not `pawn.attribute()`.** This was the one
static func plan_block_budget(pawn: PawnData) -> int:
	return maxi(1, floori(attribute(pawn, CG.Attribute.WIS)))

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
