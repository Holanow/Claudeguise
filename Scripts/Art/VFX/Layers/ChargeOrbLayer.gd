extends VFXLayer
class_name ChargeOrbLayer

## The tell. Grows at the caster across the whole wind-up, so a player can read
## that something is coming and roughly how big before it lands.
@export var inner_colour: Color = Color(1.0, 0.95, 0.7)
@export var outer_colour: Color = Color(1.0, 0.35, 0.06)
@export var size: float = 118.0
@export var offset: Vector2 = Vector2(0, -6)
@export var on_target: bool = false

func play(ctx: Dictionary) -> void:
	var director = ctx["director"]
	var who: int = ctx["target_id"] if on_target else ctx["source_id"]
	var orb: ColorRect = director.make_shader_rect("res://Shaders/VFX/charge_orb.gdshader", size)
	if orb == null:
		return
	orb.material.set_shader_parameter("inner_colour", inner_colour)
	orb.material.set_shader_parameter("outer_colour", outer_colour)
	director.follow(orb, who, offset)
	var seconds: float = ctx["seconds"]
	director.tween_shader(orb, "charge", 0.0, 1.0, seconds, Tween.EASE_IN, Tween.TRANS_QUAD)
	director.free_after(orb, seconds)

func describe() -> String:
	return "a gathering orb through the wind-up"
