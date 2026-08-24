extends Node2D
class_name ImpactFlash


## A brief coloured ring expanding and fading at the moment a hit lands --
## sable's `AttackFX.draw_impact_flash` (Scripts/Art, PR #69), wired in here.

const LIFETIME_SECONDS := 0.35

var _damage_type: CG.DamageType = CG.DamageType.PHYSICAL
var _base_radius: float = 20.0
var _age: float = 0.0
## Issue 151: an INTERRUPTED event is not damage and has no damage type, so
## borrowing one would put a lie in the vocabulary the floating numbers and the
## projectile marks share. An explicit colour instead, used only when set.
var _color_override: Color = Color(0, 0, 0, 0)
## Issue 276: the ring is sized to a body, so it has to stay on that body.
var _follow: Node2D = null

## Sibling of the unit's view under the same Arena node, so its position needs
## no transform.
func follow(node: Node2D) -> void:
	_follow = node
	if node != null:
		position = node.position

func flash(damage_type: CG.DamageType, base_radius: float) -> void:
	_damage_type = damage_type
	_color_override = Color(0, 0, 0, 0)
	_base_radius = base_radius
	_age = 0.0
	set_process(true)
	queue_redraw()

## The player asked for the stun interrupt twice over: "the stun icon should
## appear and the unit should flash white or something". The badge says what
## happened, this says it happened NOW -- which is the half a log line cannot do
## for someone watching without pausing.
func flash_color(color: Color, base_radius: float) -> void:
	_color_override = color
	_base_radius = base_radius
	_age = 0.0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	# Issue 528: a hit stop is a COMPLETE stop, and this kept expanding through it.
	if ViewClock.frozen:
		return
	if _follow != null:
		# Issue 497: the view node outlives the unit -- `_unit_views` never erases
		# and `sync` keeps moving a corpse -- so a ring that kept following one
		# drew over empty ground after 7.4% of hits. It lets go where the body
		# fell rather than being freed, or a killing blow is the one hit with no
		# mark on it.
		if not is_instance_valid(_follow):
			_follow = null
		else:
			position = _follow.position
			if not _follow.visible:
				_follow = null
	_age += delta
	if _age >= LIFETIME_SECONDS:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := _age / LIFETIME_SECONDS
	if _color_override.a <= 0.0:
		AttackFX.draw_impact_flash(self, Vector2.ZERO, _base_radius, _damage_type, progress)
		return
	var alpha := AttackFX.impact_flash_alpha(progress)
	if alpha <= 0.0:
		return
	var color := _color_override
	color.a = alpha
	draw_arc(Vector2.ZERO, AttackFX.impact_flash_radius(_base_radius, progress), 0.0, TAU, 20, color, 3.0, true)
