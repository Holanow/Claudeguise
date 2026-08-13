extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")

## A shot in flight: aimed at a fixed point captured at launch (no homing --
## that is what lets a target walk out of the way, per issue 18), travelling
## at a fixed speed toward it. Resolves when it comes within the target's own
## radius of the target's live position, or reaches its aim_point without
## that happening, whichever comes first.
##
## MANAGER-OWNED SHAPE. Instances live only in CombatState.projectiles,
## created and resolved by CombatSim (Scripts/Combat/, swift's).
##
## Append-only, same convention as CombatState.units: id is index into
## CombatState.projectiles and never changes; a resolved projectile stays in
## place with resolved == true rather than being removed, so nothing
## iterating mid-tick sees the array reshuffle.
##
## Why this is not a CombatUnit, which was swift's call and is the right one:
## a unit is a combatant that other systems reference by id for the whole
## fight, and `state.unit(id)` is a load-bearing contract. A hasted archer over
## a 3600-tick fight looses hundreds of shots and nothing outside the
## simulation ever needs to name one.
##
## The hit check uses the **target's own radius** rather than a constant of its
## own. That field already exists and already governs movement blocking, so a
## Ghoul is genuinely easier to hit than a Goblin without anybody choosing a
## number for it.

var id: int = -1

var source_id: int = -1
var target_id: int = -1
var action_id: StringName = &""

var origin: Vector2 = Vector2.ZERO
## Frozen at launch: the target's position at the moment the shot left.
## Never recomputed -- a homing projectile would defeat the point.
var aim_point: Vector2 = Vector2.ZERO
var position: Vector2 = Vector2.ZERO

## World units per tick.
var speed: float = 0.0

var spawn_tick: int = 0
var resolved: bool = false
