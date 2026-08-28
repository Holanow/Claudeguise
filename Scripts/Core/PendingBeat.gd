extends RefCounted
class_name PendingBeat

## Issue 703: one beat of a combo waiting for its own tick, resolved and
## dropped by `CombatSim._tick_beats`. A dead caster's entries are dropped
## rather than resolved. Its own file, not a nested class, on `Projectile`'s
## precedent -- a typed `Array[X]` of an inner class fails to validate once
## the owning script gets reloaded, which the test runner does to every file.

var caster_id: int = -1
var action: ActionDef = null
var beat: ActionBeat = null
var beat_index: int = -1
var resolve_tick: int = 0
