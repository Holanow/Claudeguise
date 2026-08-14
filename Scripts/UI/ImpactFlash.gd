extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const AttackFX := preload("res://Scripts/Art/AttackFX.gd")

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

func flash(damage_type: CG.DamageType, base_radius: float) -> void:
	_damage_type = damage_type
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
	AttackFX.draw_impact_flash(self, Vector2.ZERO, _base_radius, _damage_type, _age / LIFETIME_SECONDS)
