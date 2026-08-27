extends RefCounted
class_name Projectile


## A shot in flight, aimed at a point fixed at launch and re-aimed only when
## `homing_strength` (issue 671) is above zero, by up to that many degrees per
## tick toward the target's live position -- which is what lets a target walk
## out of a non-homing shot's way (issue 18). Resolves when it comes within
## the target's own radius of the target's live position, or on reaching
## aim_point, whichever is first.

var id: int = -1

var source_id: int = -1
var target_id: int = -1
var action_id: StringName = &""

var origin: Vector2 = Vector2.ZERO
## Frozen at launch. Never recomputed.
var aim_point: Vector2 = Vector2.ZERO
var position: Vector2 = Vector2.ZERO

## World units per tick.
var speed: float = 0.0

## Degrees this shot may turn toward its target each tick. 0.0 is straight.
var homing_strength: float = 0.0

var spawn_tick: int = 0
var resolved: bool = false
