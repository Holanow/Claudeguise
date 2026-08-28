extends Resource
class_name VFXLayer

## One visual thing that happens when an action does something. An action's look
## is a list of these, for the same reason its rules are a list of `AbilityEffect`:
## a new kind of flourish is a new resource rather than another exported field on
## every action that will never use it.
##
## It lives in Core, not Art, and that is load-bearing: `ActionDef` names it, and
## a simulation file that names view code breaks the separation the fingerprint
## rests on. The DESCRIPTION of a look is data; the PLAYING of it is the view,
## which is why every subclass lives under `Scripts/Art/VFX/Layers`.
enum Cue { WIND_UP, RELEASE, IMPACT }

@export var cue: Cue = Cue.IMPACT

## Issue 657. ALWAYS plays at its cue, unchanged. ON_CONSUME and
## WITHOUT_CONSUME play only once the hit is known to have (or not have)
## consumed the action's `consumes_status` -- see `VFXDirector.play_consume_gated`.
enum When { ALWAYS, ON_CONSUME, WITHOUT_CONSUME }

@export var when: When = When.ALWAYS

## Seconds to wait after the cue before starting. This is how an impact layer
## lands when a beam arrives rather than when it is fired.
@export var delay: float = 0.0

## `ctx` carries `director`, `source_id`, `target_id` and `seconds`. Layers reach
## the screen only through the director, never through the simulation.
func play(_ctx: Dictionary) -> void:
	pass

func describe() -> String:
	return "nothing"
