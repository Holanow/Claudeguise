extends VFXLayer
class_name StatusAuraLayer

## A glow that tracks its target and stays near full brightness until close to
## `seconds`, then drops fast -- unlike GlowPulseLayer's EASE_OUT, which decays
## within the first fraction of a long span. Exists for statuses the player must
## be able to read for their whole duration, not just at the instant they land:
## issue 696 names marks specifically. `seconds` is authored as the status's own
## `duration_ticks / CG.TICKS_PER_SECOND`, not the tier's impact-window budget.
@export var colour: Color = Color(1.0, 1.0, 1.0)
@export var size: float = 46.0
@export var seconds: float = 6.0

func play(ctx: Dictionary) -> void:
	var director = ctx["director"]
	var glow: ColorRect = director.make_shader_rect("res://Shaders/VFX/charge_orb.gdshader", size)
	if glow == null:
		return
	glow.material.set_shader_parameter("inner_colour", colour)
	glow.material.set_shader_parameter("outer_colour", colour)
	director.follow(glow, ctx["target_id"], Vector2(0, -34))
	director.tween_shader(glow, "charge", 1.0, 0.0, seconds, Tween.EASE_IN, Tween.TRANS_QUAD)
	director.free_after(glow, seconds)

func describe() -> String:
	return "a marker held on its target for %.1fs" % seconds
