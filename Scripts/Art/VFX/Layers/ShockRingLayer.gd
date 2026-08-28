extends VFXLayer
class_name ShockRingLayer

@export var ring_colour: Color = Color(1.0, 0.62, 0.22)
@export var size: float = 260.0
@export var seconds: float = 0.34
@export var thickness: float = 0.20
## False centres the ring on the caster instead -- a summon's "something
## arrived here" pop has nothing to do with the caster's target.
@export var on_target: bool = true

func play(ctx: Dictionary) -> void:
	var director = ctx["director"]
	var who: int = ctx["target_id"] if on_target else ctx["source_id"]
	var ring: ColorRect = director.make_shader_rect("res://Shaders/VFX/shockring.gdshader", size)
	if ring == null:
		return
	ring.material.set_shader_parameter("ring_colour", ring_colour)
	ring.material.set_shader_parameter("thickness", thickness)
	director.place(ring, director.position_of(who))
	director.tween_shader(ring, "progress", 0.0, 1.0, seconds, Tween.EASE_OUT, Tween.TRANS_CUBIC)
	director.free_after(ring, seconds)

func describe() -> String:
	return "an expanding shock ring"
