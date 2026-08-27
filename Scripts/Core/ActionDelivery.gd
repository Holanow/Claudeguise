extends Resource
class_name ActionDelivery

## How an action's effects travel to where they land. `null` on an `ActionDef`
## means instant, which is most of them.

## World units per tick.
@export var speed: float = 0.0

## Projectiles fanned evenly across `spread_degrees`, centred on the aim. 1
## with 0 spread is a single shot straight at the target, which is every
## delivery that existed before issue 671.
@export var count: int = 1

## Total angle the `count` projectiles fan across. Ignored when `count <= 1`.
@export var spread_degrees: float = 0.0

## Degrees per tick a projectile may turn toward its live target position. 0
## is straight flight, which is every delivery that existed before issue 671.
@export var homing_strength: float = 0.0
