extends AbilityEffect
class_name StepEffect

## Moves the CASTER along its own facing. Negative is backward. `PullEffect`
## already moves a target, so this is its sibling. Does not change facing.
@export var distance: float = 0.0
