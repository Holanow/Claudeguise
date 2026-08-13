extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const Silhouettes := preload("res://Scripts/Art/Silhouettes.gd")

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

## Class id for a pawn, enemy id for an enemy. Silhouettes.draw_unit falls
## back to a hollow diamond for any id it does not know, so this is safe to
## call before teal's content registers real classes or enemies.
func _shape_id(u: CombatUnit) -> StringName:
	if u.pawn != null and u.pawn.pawn_class != null:
		return u.pawn.pawn_class.id
	return u.enemy_id

## The class's first damage type colours its accent shapes. Enemies have no
## class to read one from, so they fall back to physical until there is a
## reason to look one up on EnemyDef instead.
func _accent(u: CombatUnit) -> int:
	if u.pawn != null and u.pawn.pawn_class != null and not u.pawn.pawn_class.damage_types.is_empty():
		return u.pawn.pawn_class.damage_types[0]
	return CG.DamageType.PHYSICAL

func _draw() -> void:
	var u := _unit()
	if u == null:
		return

	_draw_targeting_line(u)

	Silhouettes.draw_unit(self, _shape_id(u), u.radius, u.team, _accent(u), u.team == CG.Team.ENEMY)

	if u.action_ticks_left > 0 and u.current_action != &"":
		draw_arc(Vector2.ZERO, u.radius + 4.0, 0.0, TAU, 28, Palette.WIND_UP, 3.0, true)
		var font := ThemeDB.fallback_font
		var ticks_text := str(u.action_ticks_left)
		var text_size := font.get_string_size(ticks_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL)
		draw_string(font, Vector2(-text_size.x * 0.5, u.radius + 4.0 + text_size.y),
			ticks_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.WIND_UP)

	_draw_status_tags(u)

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

## Who is this unit currently after. Answers "why is that side winning" by
## itself, before a single number changes: a target being focused by three
## units at once reads differently from one being ignored.
func _draw_targeting_line(u: CombatUnit) -> void:
	if u.focus_id < 0 or u.current_action == &"":
		return
	var target := _state.unit(u.focus_id)
	if target == null or not target.alive:
		return
	draw_line(Vector2.ZERO, target.position - u.position, Palette.FOCUS_LINE, 2.0)

## Stunned and out-of-resource both look identical to "idle" on the arena
## otherwise: the unit just doesn't do anything, and a viewer with no access
## to CombatUnit.statuses cannot tell a stalled decision from a disabled one.
func _draw_status_tags(u: CombatUnit) -> void:
	var tags := status_tags(u)
	if tags.is_empty():
		return
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-BAR_WIDTH * 0.5, u.radius + 14.0), " ".join(tags),
		HORIZONTAL_ALIGNMENT_LEFT, BAR_WIDTH * 2.0, Palette.FONT_SIZE_SMALL, Palette.HP_LOW)

## Split out from _draw_status_tags so it can be tested without a live
## canvas: Godot refuses draw_* calls outside _draw(), so a test that calls a
## drawing function directly logs errors and asserts nothing, which is
## exactly the trap Silhouettes.build_parts's own doc comment names.
static func status_tags(u: CombatUnit) -> Array[String]:
	var tags: Array[String] = []
	if u.has_status(CG.Status.STUN):
		tags.append("STUN")
	if u.resource_max > 0 and u.resource <= 0:
		tags.append("OOM")
	return tags
