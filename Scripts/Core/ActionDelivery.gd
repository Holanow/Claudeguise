extends Resource
class_name ActionDelivery

## How an action's effects travel to where they land. `null` on an `ActionDef`
## means instant, which is most of them.

## World units per tick.
@export var speed: float = 0.0
