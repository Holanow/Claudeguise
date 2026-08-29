extends AbilityEffect
class_name HitEffect

## Damage, or a heal. One resolution path: `heals` picks the direction.

@export var damage_type: CG.DamageType = CG.DamageType.PHYSICAL

## Multiplier on the wielder's derived attack power for this damage type.
## `Balance.gd` owns what that power is; this owns how hard this hit leans on it.
@export var power_scale: float = 1.0

## Issue 772. Alternative to `power_scale`: percent of the CASTER's own max hp
## dealt per hit, same units as `StatusDef.damage_percent_of_max_hp_per_tick`.
## 0 leaves `power_scale` in charge; a caster whose damage is its own body
## (Immolate) sets this instead and leaves `power_scale` at 0.
@export var caster_max_hp_percent: float = 0.0

@export var heals: bool = false

## A status this hit strips off its target for a bonus, scaled by what that
## status was carrying. It is part of the hit rather than a sibling effect
## because it scales this same hit, and #562 is what one number driving two
## places costs when they drift apart.
@export var consumes_status_enabled: bool = false
@export var consumes_status: CG.Status = CG.Status.SHIELD
@export var consumed_power_scale: float = 0.0
