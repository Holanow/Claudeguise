extends RefCounted
class_name PendingBeat

## Issue 703: one beat of a combo waiting for its own tick, resolved and
## dropped by `CombatSim._tick_beats`. A dead caster's entries are dropped
## rather than resolved. Its own file, not a nested class, because
## `CombatState` declares `Array[PendingBeat]` and `CombatSim` builds them:
## two scripts name the type, so a global `class_name` is the honest shape.
## The test runner's `reload()`, the original reason, went with PR #872.

var caster_id: int = -1
var action: ActionDef = null
var beat: ActionBeat = null
var beat_index: int = -1
var resolve_tick: int = 0
