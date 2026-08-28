extends Resource
class_name ActionTargeting

## Who an action reaches, and under what conditions. One of the three axes an
## action is composed on; `null` on an `ActionDef` means the defaults here.

## World units. Measured centre to centre at the moment the effect lands, not at
## the moment the unit commits: a target that walks out is a miss.
@export var range_units: float = 0.0

## World units. 0.0 means the effect hits only the focused target.
@export var splash_radius: float = 0.0

## Whether this action needs an unobstructed line to its target. A wall or a
## pillar between the two stops it; a pit does not, since a pit blocks feet
## rather than sight.
@export var requires_line_of_sight: bool = false

## This action is cast on its caster, whoever that is.
@export var targets_self: bool = false

## The action names an ALLY but puts its effects on the CASTER, who turns to
## face the threat to that ally.
@export var covers_target: bool = false

## This action may only be used against a target carrying `CG.Status.MARKED`.
@export var requires_marked_target: bool = false

## 0.0 means no angular restriction, which is every action before issue 671.
## Above zero, a target must be within this many degrees of the caster's
## `facing` -- the angle between `facing` and the direction to the target,
## not a total cone width -- **and** inside `splash_radius`, which for an arc
## action is measured from the caster rather than from the primary target.
@export var arc_degrees: float = 0.0

## Issue 563. How many enemies a shot passes through. 0 is stop at the first,
## which is every action that existed before this one.
@export var pierce_count: int = 0

## Half the width of the corridor a piercing shot sweeps.
@export var pierce_half_width: float = 0.0
