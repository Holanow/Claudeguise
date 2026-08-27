extends VFXLayer
class_name EmberBurstLayer

## CPUParticles2D rather than GPU: this project ships the compatibility
## renderer, and at forty particles the difference is not worth the risk.
@export var amount: int = 46
@export var colour_hot: Color = Color(1.0, 0.85, 0.45)
@export var colour_cool: Color = Color(0.75, 0.13, 0.03)
@export var speed: float = 340.0
@export var lifetime: float = 0.85
@export var gravity: Vector2 = Vector2(0, -120)
@export var explosive: bool = true

func play(ctx: Dictionary) -> void:
	var director = ctx["director"]
	director.burst(director.position_of(ctx["target_id"]),
		amount, colour_hot, colour_cool, speed, lifetime, gravity, explosive)

func describe() -> String:
	return "an ember burst"
