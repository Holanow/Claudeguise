extends VFXLayer
class_name ArcSweepLayer

## The arc an action actually hits, swept from one edge to the other. `radius`
## and `half_arc_degrees` are meant to be the action's own `splash_radius` and
## `arc_degrees`: an arc drawn wider than its hitbox is a lie the player learns
## the hard way.
@export var edge_colour: Color = Color(0.72, 0.86, 1.0)
@export var core_colour: Color = Color(1.0, 1.0, 1.0)
@export var radius: float = 65.0
@export var half_arc_degrees: float = 65.0
@export var sweep_seconds: float = 0.16
@export var fade_seconds: float = 0.18
@export var inner_fraction: float = 0.35

## Issue 703. The shader's `progress` always sweeps its leading edge 0 -> 1
## across the arc; tweening it 1 -> 0 sweeps the other way, no shader change.
@export var reverse: bool = false

func play(ctx: Dictionary) -> void:
	var director = ctx["director"]
	var arc: ColorRect = director.make_shader_rect("res://Shaders/VFX/arc_sweep.gdshader", radius * 2.0)
	if arc == null:
		return
	arc.material.set_shader_parameter("edge_colour", edge_colour)
	arc.material.set_shader_parameter("core_colour", core_colour)
	arc.material.set_shader_parameter("half_arc_radians", deg_to_rad(half_arc_degrees))
	arc.material.set_shader_parameter("inner", inner_fraction)
	director.aim(arc, ctx["source_id"])
	var start := 1.0 if reverse else 0.0
	var end := 0.0 if reverse else 1.0
	director.tween_shader(arc, "progress", start, end, sweep_seconds, Tween.EASE_OUT, Tween.TRANS_QUAD)
	director.tween_shader(arc, "fade", 1.0, 0.0, fade_seconds, Tween.EASE_IN, Tween.TRANS_QUAD, sweep_seconds)
	director.free_after(arc, sweep_seconds + fade_seconds)

func describe() -> String:
	return "a %.0f-degree arc swept to %.0f units" % [half_arc_degrees * 2.0, radius]
