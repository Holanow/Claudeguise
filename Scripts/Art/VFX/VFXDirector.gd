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
var shake_fn: Callable = func(_pixels: float) -> void: pass
var hit_stop_fn: Callable = func() -> void: pass

var _rng := RandomNumberGenerator.new()
var _followers: Array[Node2D] = []

func _ready() -> void:
	_rng.seed = 12345

func position_of(id: int) -> Vector2:
	return position_of_fn.call(id)

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
		holder.position = position_of(int(holder.get_meta(&"unit_id"))) \
			+ Vector2(holder.get_meta(&"offset"))

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

## Tracks a unit for as long as it lives, which a wind-up tell needs because the
## caster is often still walking when it starts.
func follow(rect: ColorRect, unit_id: int, offset: Vector2) -> void:
	var holder := rect.get_parent() as Node2D
	holder.set_meta(&"unit_id", unit_id)
	holder.set_meta(&"offset", offset)
	holder.position = position_of(unit_id) + offset
	_followers.append(holder)

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
