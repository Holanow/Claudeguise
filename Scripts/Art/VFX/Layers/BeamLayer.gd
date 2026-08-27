extends VFXLayer
class_name BeamLayer

## Caster's chest to the target. The player's own framing: the root of a geyser
## is the chest, not a muzzle.
@export var core_colour: Color = Color(1.0, 0.98, 0.85)
@export var edge_colour: Color = Color(1.0, 0.30, 0.05)
@export var width: float = 74.0
@export var extend_seconds: float = 0.07
@export var hold_seconds: float = 0.10
@export var fade_seconds: float = 0.22
@export var offset: Vector2 = Vector2(0, -6)
## The player's note: a beam should leave the hands, not the chest.
@export var from_hands: bool = true
## Which hand. -1 is the midpoint of all of them, which is a two-handed cast.
@export var hand_index: int = -1

func play(ctx: Dictionary) -> void:
	var director = ctx["director"]
	var from: Vector2 = director.anchor_of(ctx["source_id"], from_hands, hand_index) + offset
	var to: Vector2 = director.position_of(ctx["target_id"])
	if from == to:
		return
	var beam: ColorRect = director.make_beam("res://Shaders/VFX/beam.gdshader", from, to, width)
	if beam == null:
		return
	director.follow_beam(beam, ctx["source_id"], from_hands, to, hand_index)
	beam.material.set_shader_parameter("core_colour", core_colour)
	beam.material.set_shader_parameter("edge_colour", edge_colour)
	director.tween_shader(beam, "extend", 0.0, 1.0, extend_seconds, Tween.EASE_OUT, Tween.TRANS_EXPO)
	director.tween_shader(beam, "fade", 1.0, 0.0, fade_seconds, Tween.EASE_IN, Tween.TRANS_QUAD,
		extend_seconds + hold_seconds)
	director.free_after(beam, extend_seconds + hold_seconds + fade_seconds)

func describe() -> String:
	return "a beam from the caster's chest"
