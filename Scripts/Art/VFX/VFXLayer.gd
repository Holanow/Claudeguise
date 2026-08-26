extends Resource
class_name VFXLayer

## One visual thing that happens when an action does something. An action's look
## is a list of these, for the same reason its rules are a list of `AbilityEffect`:
## a new kind of flourish is a new resource rather than another exported field on
## every action that will never use it.
##
## Ported from the god-guise proof. The primitives it composes -- shake, hit stop,
## bursts -- already existed in `BattleView`; what did not exist was any way for
## one action to say which of them it wants.
enum Cue { WIND_UP, RELEASE, IMPACT }

@export var cue: Cue = Cue.IMPACT

## Seconds to wait after the cue before starting. This is how an impact layer
## lands when a beam arrives rather than when it is fired.
@export var delay: float = 0.0

## `ctx` carries `director`, `source_id`, `target_id` and `seconds`. Layers reach
## the screen only through the director, never through the simulation.
func play(_ctx: Dictionary) -> void:
	pass

func describe() -> String:
	return "nothing"
