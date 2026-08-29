extends AbilityEffect
class_name StatusEffect

## A status put on the target for a span of ticks.

@export var status: CG.Status = CG.Status.SHIELD
@export var duration_ticks: int = 0

## What the status is CARRYING, authored here rather than derived from the hit.
## 0.0 means it stores nothing here; `warrior_block` carries its pool as a
## share of caster health instead.
@export var magnitude: float = 0.0

## `magnitude` as a share of the CASTER's max health instead of a flat number,
## in percent, the same units as `HitEffect.caster_max_hp_percent`. Overrides
## `magnitude` when above zero.
@export var magnitude_caster_max_hp_percent: float = 0.0

## The caster's cooldown on this action does not start until this status leaves
## its target, so the action cannot be re-cast while it is still up.
@export var holds_cooldown: bool = false

## How far a TAUNTING reaches, in world units. It belongs to the status rather
## than to the action: the reach is what the taunt does, not a second effect.
@export var taunt_radius: float = 0.0
