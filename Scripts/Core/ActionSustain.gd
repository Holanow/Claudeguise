extends Resource
class_name ActionSustain

## A state the caster enters and pays for, rather than an action that arrives.
## Sustained actions have no moment of impact, so they do not fit the three
## axes and get this instead.

## Resource charged to the caster on every tick the action is held.
@export var cost_per_tick: int = 0

## World units the held action reaches while it is up.
@export var radius: float = 0.0
