extends AbilityEffect
class_name SummonEffect

## Builds units on the caster's own team. Resolved at the caster, not at a
## target, so the sim dispatches it from `_fire_action` rather than per target.

@export var unit_id: StringName = &""

## The most from this effect that may be alive at once. Zero means no limit.
@export var max_active: int = 0
