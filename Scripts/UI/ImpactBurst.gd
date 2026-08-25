extends Node2D
class_name ImpactBurst


## Issue 517. The debris every hit throws, out of one fixed pool of emitters.
##
## A `GPUParticles2D` per hit is a node and a GPU buffer per DAMAGE event, which
## is how "the count is the risk" comes true. The pool is a hard cap instead:
## the oldest burst is recycled, so a scrum cannot grow the live count past
## `POOL * PER_BURST` however many hits land in it.

## `Assets/UI/fx/impact.png`, white so the damage colour can tint it. Missing,
## it is a black square -- the project's ruling, and deliberate.
const SPRITE := &"fx/impact"

## Measured, not guessed: `Tools/ParticleCost.gd` reports the bursts a real
## scrum wants alive at once, and this is set above it.
const POOL := 24
const PER_BURST := 8
const LIFETIME := 0.35

var _emitters: Array[GPUParticles2D] = []
## Each emitter's own speed, so the freeze can zero `speed_scale` and give the
## right one back rather than the same one to all of them.
var _speeds: Array[float] = []
var _next: int = 0
var _frozen: bool = false

func _ready() -> void:
	var texture := UIArt.texture_for(SPRITE)
	if texture == null:
		texture = _black_square()
	var material := _material()
	for i in POOL:
		var p := GPUParticles2D.new()
		p.texture = texture
		# One material for the whole pool. Duplicating it per burst is the other
		# half of the cost this pool exists to avoid.
		p.process_material = material
		p.amount = PER_BURST
		p.lifetime = LIFETIME
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		# Debris is thrown off a body and then belongs to the ground, not to the
		# body, so it must not ride the emitter when the next burst moves it.
		p.local_coords = false
		add_child(p)
		_emitters.append(p)
		_speeds.append(1.0)

## Fires at `at`, in the damage type's own colour and speed.
func burst(at: Vector2, damage_type: CG.DamageType) -> void:
	_fire(at, Palette.damage_color(damage_type), _speed_for(damage_type))

## Issue 589. The same pool, louder. A death throws further and faster than a
## hit, and it throws the dying unit's own colour rather than the colour of
## whatever finished it: the chunks flying beside it are that unit as well.
const DEATH_SPEED := 2.4
const DEATH_BURSTS := 2

func death_burst(at: Vector2, color: Color) -> void:
	for i in DEATH_BURSTS:
		_fire(at, color, DEATH_SPEED)

func _fire(at: Vector2, color: Color, speed: float) -> void:
	var i := _next
	_next = (_next + 1) % _emitters.size()
	var p := _emitters[i]
	p.position = at
	p.modulate = color
	_speeds[i] = speed
	p.speed_scale = 0.0 if _frozen else speed
	p.restart()
	p.emitting = true

## Issue 528, and from the first line rather than after: a hit stop is a
## COMPLETE stop. One check for the whole pool, on change only.
func _process(_delta: float) -> void:
	if ViewClock.frozen == _frozen:
		return
	_frozen = ViewClock.frozen
	for i in _emitters.size():
		_emitters[i].speed_scale = 0.0 if _frozen else _speeds[i]

## How many bursts are still throwing debris. The instrument reads this; nothing
## in the view does.
func live_bursts() -> int:
	var n := 0
	for p in _emitters:
		if p.emitting:
			n += 1
	return n

## Scalding water and a sword should not throw the same debris. Colour carries
## most of it, from the same `Palette.damage_color` the floating numbers use;
## this is the second axis, and it is the only one a shared material allows.
func _speed_for(damage_type: CG.DamageType) -> float:
	match damage_type:
		CG.DamageType.PHYSICAL: return 1.3
		CG.DamageType.AIR: return 1.5
		CG.DamageType.RAW: return 1.2
		CG.DamageType.EARTH: return 0.9
		CG.DamageType.FIRE: return 0.8
		CG.DamageType.DIVINE, CG.DamageType.PROFANE: return 0.7
	return 1.0

func _material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 180.0
	m.initial_velocity_min = 70.0
	m.initial_velocity_max = 220.0
	m.gravity = Vector3(0.0, 320.0, 0.0)
	m.damping_min = 20.0
	m.damping_max = 60.0
	m.scale_min = 0.06
	m.scale_max = 0.16
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	m.color_ramp = ramp_texture
	return m

func _black_square() -> Texture2D:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	return ImageTexture.create_from_image(image)
