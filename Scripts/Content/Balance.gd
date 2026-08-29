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

## Issue 491: 1.9 x the mean starting-weapon grant. Every pawn has always held
## a weapon, so a class's real damage was always its base times that multiplier;
## #489 removed the multiplier and revealed that the base was never the whole
## number. The five grants were sword STR 15%, staff INT 12%, orb INT 18%, bow
## DEX 15% and sickle INT 15%, and their mean is exactly 15%.
const ATTACK_POWER_PER_POINT := 2.185

## Issue 7: a hit rolls within [1 - spread, 1 + spread] of its base power.
const ATTACK_VARIANCE_SPREAD := 0.55

const DAMAGE_REDUCTION_PER_CON := 0.01
const NATURAL_DAMAGE_REDUCTION_CAP := 0.9
const MAX_DAMAGE_REDUCTION := 0.9

## Fraction shaved off an action's ticks per point of AGI. Issue 592 raised the
## cap to 0.9; `scale_action_ticks` floors the resolved count at one tick, so
## nothing here can take an action to zero.
const AGI_TICK_SCALE_PER_POINT := 0.015
const MAX_AGI_TICK_SCALE := 0.9

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

## Issue 627: the five per-status numbers that used to sit here -- poison's
## percent, burn's fraction of the hit, bleed's per-stack damage, haste's tick
## scale and slowed's speed scale -- are fields on the `StatusDef` for each
## status. The functions below still read them; they read one file per status
## instead of five constants that nothing tied to the statuses they described.

## Issue 39: an attribute including equipment's `attribute_flat` and
## `attribute_percent` (weapons and accessories: percent per README.md; armor:
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

## Issue 746: the best `damage_reduction` across every equipped item, not just
## `body`. A shield in `off_hand` carries the same field body armor always has,
## so a single-slot read stops seeing it. Best rather than summed: two items
## both reducing damage is not twice the protection.
static func gear_damage_reduction(pawn: PawnData) -> float:
	var best := 0.0
	for e in pawn.equipment():
		best = maxf(best, e.damage_reduction)
	return best

## Fraction of incoming damage removed, from armor, natural toughness and
## statuses. The simulation applies this; it does not decide it.
static func damage_reduction(unit: CombatUnit) -> float:
	var reduction := 0.0
	if unit.pawn != null:
		reduction = clampf(attribute(unit.pawn, CG.Attribute.CON) * DAMAGE_REDUCTION_PER_CON, 0.0, NATURAL_DAMAGE_REDUCTION_CAP)
		reduction += gear_damage_reduction(unit.pawn)
	else:
		var enemy_def: EnemyDef = EnemyLibrary.get_enemy(unit.enemy_id)
		if enemy_def != null:
			reduction = enemy_def.damage_reduction
	## Three statuses, named one at a time rather than looped over whatever the
	## unit is carrying: float addition is not associative, and `unit.statuses`
	## is in the order the statuses happened to land in.
	if unit.has_status(CG.Status.SHIELD):
		reduction += StatusLibrary.of(CG.Status.SHIELD).damage_reduction
	if unit.has_status(CG.Status.BLOCK):
		reduction += StatusLibrary.of(CG.Status.BLOCK).damage_reduction
	if unit.has_status(CG.Status.MARKED):
		reduction -= StatusLibrary.of(CG.Status.MARKED).vulnerability
	return clampf(reduction, 0.0, MAX_DAMAGE_REDUCTION)

## How many blocks a pawn's plans may total, from WIS per README.md.
##
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

## Issue 542. The enemy half of `scale_action_ticks`, and it is new capability
## rather than a conversion: an enemy had no action speed at all and every enemy
## action ran at exactly its authored tick counts.
##
## Clamped at both ends. The fast end mirrors the pawn's -50% floor; the slow end
## stops a small multiplier turning a wind-up into a stall nobody can read.
const MIN_ENEMY_TICK_SCALE := 0.5
const MAX_ENEMY_TICK_SCALE := 2.0

static func scale_enemy_action_ticks(base_ticks: int, action_speed: float) -> int:
	if base_ticks <= 0:
		return base_ticks
	if action_speed <= 0.0:
		return base_ticks
	var scale := clampf(1.0 / action_speed, MIN_ENEMY_TICK_SCALE, MAX_ENEMY_TICK_SCALE)
	return maxi(1, int(round(float(base_ticks) * scale)))

## What a pawn's resource pool holds at the moment a fight starts.
##
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
	if unit.pawn != null:
		for e in unit.pawn.equipment():
			percent_per_second += e.resource_regen_percent_bonus
	return float(unit.resource_max) * (percent_per_second / 100.0) / float(CG.TICKS_PER_SECOND)

## Rage gained the moment an attack lands. 0.0 for any other resource kind:
## Mana and Energy regenerate on a timer instead, never from landing a hit.
static func rage_gain_per_attack(unit: CombatUnit) -> float:
	if unit.resource_kind != CG.ResourceKind.RAGE:
		return 0.0
	return float(unit.resource_max) * (RAGE_GAIN_PERCENT_PER_HIT / 100.0)

## Damage dealt by one damage-over-time tick, from the victim's own max hp. A
## status whose def carries no percent returns 0.0, which is every status but
## POISON today.
static func status_damage_per_tick(unit: CombatUnit, status: CG.Status) -> float:
	return float(unit.hp_max) * (StatusLibrary.of(status).damage_percent_of_max_hp_per_tick / 100.0)

## Damage per tick contributed by each unit of a status's stored magnitude, on
## top of `status_damage_per_tick`. Burn scales off the hit that lit it, bleed
## off its stack count; both numbers are on the def now.
static func status_damage_per_magnitude(unit: CombatUnit, status: CG.Status) -> float:
	var _unused := unit
	return StatusLibrary.of(status).damage_per_magnitude_per_tick

## Multiplier on wind-up/recovery ticks for a unit carrying HASTE. `unit` is
## accepted for the call shape SimDeps expects; the multiplier itself is flat
## across every unit for this slice, same as attack variance was before it
## needed a per-class knob.
static func haste_tick_scale(unit: CombatUnit) -> float:
	var _unused := unit
	return StatusLibrary.of(CG.Status.HASTE).tick_scale

## Multiplier on move_speed for a unit carrying SLOWED. `unit` is accepted
## for the call shape SimDeps expects (same reasoning as haste_tick_scale
## above); the multiplier is flat across every unit for this slice.
static func slowed_speed_scale(unit: CombatUnit) -> float:
	var _unused := unit
	return StatusLibrary.of(CG.Status.SLOWED).speed_scale

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
