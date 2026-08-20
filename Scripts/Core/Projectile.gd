extends RefCounted
class_name Projectile


## A shot in flight, aimed at a point fixed at launch. No homing, which is what
## lets a target walk out of the way (issue 18). Resolves when it comes within
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

var spawn_tick: int = 0
var resolved: bool = false
