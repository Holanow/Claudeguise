extends Node2D
class_name ImpactFlash


## A brief coloured ring expanding and fading at the moment a hit lands --
## sable's `AttackFX.draw_impact_flash` (Scripts/Art, PR #69), wired in here.
## Same shape as DamageFloater.gd: purely cosmetic, driven by wall clock, and
## must never feed anything back into the simulation.
##
## OWNER: wren.
##
## The piece melee attacks had nothing of before this — a Strike and a
## Smite used to look identical on screen except for the log line and the
## floating number. `AttackFX` owns the geometry and colour (keyed on
## damage type, same vocabulary the floating numbers already use);
## everything below is just "how long is this on screen", the same split
## DamageFloater already draws between itself and BattleView.

const LIFETIME_SECONDS := 0.35

var _damage_type: CG.DamageType = CG.DamageType.PHYSICAL
var _base_radius: float = 20.0
var _age: float = 0.0
## Issue 151: an INTERRUPTED event is not damage and has no damage type, so
## borrowing one would put a lie in the vocabulary the floating numbers and the
## projectile marks share. An explicit colour instead, used only when set.
##
## The geometry still comes from `AttackFX.impact_flash_radius` and
## `impact_flash_alpha`, the same two functions `AttackFX.draw_impact_flash`
## calls, so an interrupt flash and a hit flash move identically and only the
## colour differs. Nothing in Scripts/Art changed -- that is sable's.
var _color_override: Color = Color(0, 0, 0, 0)

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
