extends VFXLayer
class_name GlowPulseLayer

## A bloom over the struck body, drawn rather than tinting the unit: unit parts
## are painted with `draw_texture_rect`, so there is no sprite to modulate.
@export var colour: Color = Color(1.0, 0.96, 0.88)
@export var size: float = 90.0
@export var seconds: float = 0.16

func play(ctx: Dictionary) -> void:
	var director = ctx["director"]
	var glow: ColorRect = director.make_shader_rect("res://Shaders/VFX/charge_orb.gdshader", size)
	if glow == null:
		return
	glow.material.set_shader_parameter("inner_colour", colour)
	glow.material.set_shader_parameter("outer_colour", colour)
	director.follow(glow, ctx["target_id"], Vector2.ZERO)
	director.tween_shader(glow, "charge", 1.0, 0.0, seconds, Tween.EASE_OUT, Tween.TRANS_QUAD)
	director.free_after(glow, seconds)

func describe() -> String:
	return "a bloom on the struck body"
