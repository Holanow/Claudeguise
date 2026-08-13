extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")

## One combatant on screen: body, health bar, resource bar, name, tags, and the
## wind-up indicator that says an action is coming.
##
## OWNER: pike.
##
## The wind-up indicator is not decoration. ActionDef.wind_up_ticks exists so a
## fight can be read rather than watched, and that only works if the screen
## shows it.
##
## Positions and bars read CombatUnit directly. Anything that *happened* (a
## death being announced, a number floating) comes from a CombatEvent instead,
## handled by BattleView and DamageFloater.

const BAR_WIDTH := 36.0
const BAR_HEIGHT := 5.0
const BAR_GAP := 2.0

var unit_id: int = -1
var _state: CombatState = null

func bind(state: CombatState, id: int) -> void:
	unit_id = id
	sync(state)

func sync(state: CombatState) -> void:
	_state = state
	var u := _unit()
	if u == null:
		return
	position = u.position
	visible = u.alive
	queue_redraw()

func _unit() -> CombatUnit:
	if _state == null:
		return null
	return _state.unit(unit_id)

func _draw() -> void:
	var u := _unit()
	if u == null:
		return

	draw_circle(Vector2.ZERO, u.radius, Palette.team_color(u.team))

	if u.action_ticks_left > 0 and u.current_action != &"":
		draw_arc(Vector2.ZERO, u.radius + 4.0, 0.0, TAU, 28, Palette.WIND_UP, 2.0, true)

	# Stacked bottom-up, closest to the unit first: resource, then hp, then the
	# name. draw_string's position is a baseline, not a top-left corner, so the
	# label sits an extra font-height above where the last bar was drawn.
	var y := -u.radius - BAR_GAP

	if u.resource_max > 0:
		y -= BAR_HEIGHT
		var res_pos := Vector2(-BAR_WIDTH * 0.5, y)
		var res_fraction := float(u.resource) / float(u.resource_max)
		draw_rect(Rect2(res_pos, Vector2(BAR_WIDTH, BAR_HEIGHT)), Palette.HP_BACK)
		draw_rect(Rect2(res_pos, Vector2(BAR_WIDTH * res_fraction, BAR_HEIGHT)), Palette.resource_color(u.resource_kind))
		y -= BAR_GAP

	y -= BAR_HEIGHT
	var hp_pos := Vector2(-BAR_WIDTH * 0.5, y)
	draw_rect(Rect2(hp_pos, Vector2(BAR_WIDTH, BAR_HEIGHT)), Palette.HP_BACK)
	draw_rect(Rect2(hp_pos, Vector2(BAR_WIDTH * u.hp_fraction(), BAR_HEIGHT)), Palette.hp_color(u.hp_fraction()))
	y -= BAR_GAP + Palette.FONT_SIZE_SMALL

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-BAR_WIDTH * 0.5, y), u.display_name, HORIZONTAL_ALIGNMENT_LEFT, BAR_WIDTH * 2.0, Palette.FONT_SIZE_SMALL, Palette.TEXT)
