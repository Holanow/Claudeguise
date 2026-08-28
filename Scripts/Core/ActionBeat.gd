extends Resource
class_name ActionBeat

## One timed part of a multi-part action. Composition is by listing: an
## `ActionDef` with a non-empty `beats` fires each of these instead of its own
## `targeting`/`effects` once. Issue 703.

## Ticks after the action fires. 0 is the instant it lands.
@export var delay_ticks: int = 0

## Null falls back to the action's own targeting, so a beat only states what
## differs from it.
@export var targeting: ActionTargeting = null
@export var effects: Array[AbilityEffect] = []
@export var vfx: AbilityVFX = null
