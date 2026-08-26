extends AbilityEffect
class_name PullEffect

## Drags the target toward the caster over `CombatSim.PULL_TICKS`.

## World units. The target is stunned for exactly the span of the drag, so the
## stun is a flag here rather than a `StatusEffect` beside it: #562 established
## that one constant has to drive both or the two drift apart.
@export var distance: float = 0.0
@export var stuns: bool = true

func needs_live_target() -> bool:
	return true
