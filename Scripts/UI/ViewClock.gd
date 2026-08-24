extends RefCounted
class_name ViewClock


## Whether the presentation is holding still. `BattleView`'s hit stop owns it,
## and anything that animates on real delta reads it and does nothing while it
## is true -- issue 528, where two overlays drifted through the freeze.
static var frozen: bool = false

## Back to running. Exists for tests, which would otherwise leak one test's
## freeze into the next through the static.
static func reset() -> void:
	frozen = false
