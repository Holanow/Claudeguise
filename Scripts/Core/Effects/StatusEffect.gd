extends AbilityEffect
class_name StatusEffect

## A status put on the target for a span of ticks.

@export var status: CG.Status = CG.Status.SHIELD
@export var duration_ticks: int = 0

## What the status is CARRYING, authored here rather than derived from the hit.
## 0.0 means it stores nothing, which is every status but `warrior_block`'s.
@export var magnitude: float = 0.0

## How far a TAUNTING reaches, in world units. It belongs to the status rather
## than to the action: the reach is what the taunt does, not a second effect.
@export var taunt_radius: float = 0.0
