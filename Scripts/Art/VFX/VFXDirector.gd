extends Node2D
class_name VFXDirector

## Plays whatever an action's own `AbilityVFX` asks for. It knows how to draw
## and nothing about what actions mean; the simulation knows what actions mean
## and nothing about drawing.
##
## Shake and hit stop are NOT reimplemented here. They are Callables the view
## supplies, so the player's display toggles keep deciding whether they happen.

## id -> Vector2 in this node's own space. Supplied by the view.
var position_of_fn: Callable = func(_id: int) -> Vector2: return Vector2.ZERO
## Where the unit's hands are. Falls back to the body when a recipe has none.
var hand_of_fn: Callable = func(_id: int) -> Vector2: return Vector2.ZERO
## Every hand, tracked separately. A layer picks one by index.
var hands_of_fn: Callable = func(_id: int) -> PackedVector2Array: return PackedVector2Array()
## Which way a caster is facing. An arc has to point somewhere.
var facing_of_fn: Callable = func(_id: int) -> Vector2: return Vector2.RIGHT
var shake_fn: Callable = func(_pixels: float) -> void: pass
var hit_stop_fn: Callable = func() -> void: pass

var _rng := RandomNumberGenerator.new()
var _followers: Array[Node2D] = []
var _beams: Array[Node2D] = []

func _ready() -> void:
	_rng.seed = 12345

func position_of(id: int) -> Vector2:
	return position_of_fn.call(id)

func hand_of(id: int) -> Vector2:
	return hand_of_fn.call(id)

## One hand by index. Out of range, or -1, falls back to the midpoint of them
## all, which is what a two-handed cast wants.
func hand_at(id: int, index: int) -> Vector2:
	var points: PackedVector2Array = hands_of_fn.call(id)
	if index >= 0 and index < points.size():
		return points[index]
	return hand_of(id)

## Layers ask for an anchor by name rather than choosing a Callable themselves.
func anchor_of(id: int, hands: bool, hand_index: int = -1) -> Vector2:
	if not hands:
		return position_of(id)
	return hand_at(id, hand_index)

func shake(pixels: float) -> void:
	shake_fn.call(pixels)

func hit_stop() -> void:
	hit_stop_fn.call()

## Entry point. `seconds` is how long the cue itself lasts, which a wind-up
## layer needs and an impact layer ignores.
func play(vfx: AbilityVFX, cue: VFXLayer.Cue, source_id: int, target_id: int, seconds: float) -> void:
	if vfx == null:
		return
	for layer in vfx.for_cue(cue):
		var ctx := {
			"director": self, "source_id": source_id,
			"target_id": target_id, "seconds": seconds,
		}
		if layer.delay <= 0.0:
			layer.play(ctx)
		else:
			var l := layer
			after(layer.delay, func(): l.play(ctx))

func _process(_delta: float) -> void:
	for i in range(_followers.size() - 1, -1, -1):
		var holder := _followers[i]
		if not is_instance_valid(holder):
			_followers.remove_at(i)
			continue
		holder.position = anchor_of(int(holder.get_meta(&"unit_id")),
			bool(holder.get_meta(&"hands"))) + Vector2(holder.get_meta(&"offset"))
	for i in range(_beams.size() - 1, -1, -1):
		var beam := _beams[i]
		if not is_instance_valid(beam):
			_beams.remove_at(i)
			continue
		var rect: ColorRect = beam.get_meta(&"rect")
		if not is_instance_valid(rect):
			_beams.remove_at(i)
			continue
		var from := anchor_of(int(beam.get_meta(&"unit_id")), bool(beam.get_meta(&"hands")),
			int(beam.get_meta(&"hand")))
		var to: Vector2 = beam.get_meta(&"to")
		## #562: a beam that must outlive its impact (the Abomination's pull)
		## tracks the target's drawn position instead of the point it hit.
		## `position_of` returns ZERO once the target leaves `_unit_views`; that
		## reads as a teleport to the corner, so a dead target keeps the beam's
		## last real position instead (#497 is the same trap on a different layer).
		var track_id := int(beam.get_meta(&"track_id", -1))
		if track_id >= 0:
			var live := position_of(track_id)
			if live != Vector2.ZERO:
				to = live
				beam.set_meta(&"to", to)
		beam.position = from
		beam.rotation = (to - from).angle()
		rect.size.x = from.distance_to(to)

# ---------------------------------------------------------------------------
# Primitives. Everything a layer may do to the screen is here, which is what
# stops a layer reaching into the tree on its own.
# ---------------------------------------------------------------------------

## A square of shader centred on wherever it is placed.
func make_shader_rect(shader_path: String, size: float) -> ColorRect:
	var shader := load(shader_path)
	if shader == null:
		return null
	var rect := ColorRect.new()
	rect.size = Vector2(size, size)
	rect.position = -rect.size * 0.5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	var holder := Node2D.new()
	holder.add_child(rect)
	add_child(holder)
	return rect

## A rectangle stretched from `from` to `to`, so the shader works in a UV space
## where x runs along the beam and y across it.
func make_beam(shader_path: String, from: Vector2, to: Vector2, width: float) -> ColorRect:
	var shader := load(shader_path)
	if shader == null:
		return null
	var rect := ColorRect.new()
	rect.size = Vector2(from.distance_to(to), width)
	rect.position = Vector2(0, -width * 0.5)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	var holder := Node2D.new()
	holder.add_child(rect)
	holder.position = from
	holder.rotation = (to - from).angle()
	add_child(holder)
	return rect

## Re-roots a beam on its caster every frame. Without this the origin is fixed
## where the hands were at the instant it fired, and the hands then keep moving
## through the recover and the idle bob, so the beam visibly detaches from the
## pose throwing it. The far end stays where the blast landed.
## `track_id`, if not -1, keeps the far end on that unit's live position for as
## long as the beam lives, rather than the point it hit -- see #562.
func follow_beam(rect: ColorRect, source_id: int, hands: bool, to: Vector2, hand_index: int = -1,
		track_id: int = -1) -> void:
	var holder := rect.get_parent() as Node2D
	holder.set_meta(&"unit_id", source_id)
	holder.set_meta(&"hands", hands)
	holder.set_meta(&"to", to)
	holder.set_meta(&"hand", hand_index)
	holder.set_meta(&"rect", rect)
	holder.set_meta(&"track_id", track_id)
	_beams.append(holder)

## Tracks a unit for as long as it lives, which a wind-up tell needs because the
## caster is often still walking when it starts.
func follow(rect: ColorRect, unit_id: int, offset: Vector2, hands: bool = false) -> void:
	var holder := rect.get_parent() as Node2D
	holder.set_meta(&"unit_id", unit_id)
	holder.set_meta(&"offset", offset)
	holder.set_meta(&"hands", hands)
	holder.position = anchor_of(unit_id, hands) + offset
	_followers.append(holder)

## Centres a rect on a unit and turns it to face the way that unit does, so a
## shader can work in a local space where +X is forward.
func aim(rect: ColorRect, unit_id: int) -> void:
	var holder := rect.get_parent() as Node2D
	holder.position = position_of(unit_id)
	var facing: Vector2 = facing_of_fn.call(unit_id)
	holder.rotation = facing.angle() if facing.length() > 0.001 else 0.0

func place(rect: ColorRect, at: Vector2) -> void:
	(rect.get_parent() as Node2D).position = at

func tween_shader(rect: ColorRect, param: String, from_value: float, to_value: float,
		seconds: float, ease_type: int = Tween.EASE_IN_OUT,
		trans: int = Tween.TRANS_LINEAR, delay: float = 0.0) -> void:
	rect.material.set_shader_parameter(param, from_value)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(
		func(v: float): if is_instance_valid(rect): rect.material.set_shader_parameter(param, v),
		from_value, to_value, seconds).set_ease(ease_type).set_trans(trans)

func free_after(rect: ColorRect, seconds: float) -> void:
	var holder := rect.get_parent()
	after(seconds, func():
		if is_instance_valid(holder):
			_followers.erase(holder)
			_beams.erase(holder)
			holder.queue_free())

## A timer that ignores time scale, so a hit stop cannot strand a cleanup.
func after(seconds: float, what: Callable) -> void:
	get_tree().create_timer(seconds, true, false, true).timeout.connect(what)

func burst(at: Vector2, amount: int, hot: Color, cool: Color, speed: float,
		lifetime: float, gravity: Vector2, explosive: bool) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0 if explosive else 0.35
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = gravity
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.5
	p.damping_min = 90.0
	p.damping_max = 220.0
	var ramp := Gradient.new()
	ramp.set_color(0, hot)
	ramp.set_color(1, Color(cool.r, cool.g, cool.b, 0.0))
	ramp.add_point(0.35, cool)
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	after(lifetime * 2.0, func(): if is_instance_valid(p): p.queue_free())
