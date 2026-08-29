extends AbilityEffect
class_name ThrowEffect

## Hurls the target across the arena over `CombatSim.THROW_TICKS` and detonates
## where it lands. `PullEffect` drags toward the caster; this throws at a spot.

## World units. How far the caster can throw, measured from where the thrown
## unit is standing when it leaves the ground.
@export var max_distance: float = 0.0

## The action fired at the landing point, against everyone its own
## `splash_radius` catches. The thrown unit is at the centre, so it is caught
## by this too -- which is the second of its two hits.
@export var landing_action: StringName = &""

func needs_live_target() -> bool:
	return true
