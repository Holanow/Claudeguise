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

## Scaled for CombatUnit.radius's phone-legibility pass (12.0 -> 22.0) and
## Palette.FONT_SIZE_SMALL going 11 -> 16 alongside it.
const BAR_WIDTH := 60.0
const BAR_HEIGHT := 7.0
const BAR_GAP := 3.0

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
	position = u.position + visual_offset(u, state.units)
	visible = u.alive
	queue_redraw()

## The melee scrum: several units standing close enough that bodies occlude
## each other, called out in issue 15 as "the most important square inch of
## the screen is the least legible one". A view-only nudge, never fed back
## into CombatState — the simulation's positions are wren's and this changes
## nothing about range, targeting or movement, only where a body is drawn.
## Each overlapping pair pushes apart along the line between them; capped so
## a crowded unit never reads somewhere misleadingly far from where it
## actually is.
const _SEPARATION_PADDING := 1.3
const _SEPARATION_STRENGTH := 0.5

static func visual_offset(u: CombatUnit, units: Array) -> Vector2:
	var push := Vector2.ZERO
	for other in units:
		if other.id == u.id or not other.alive:
			continue
		var delta: Vector2 = u.position - other.position
		var dist: float = delta.length()
		var min_dist: float = (u.radius + other.radius) * _SEPARATION_PADDING
		if dist >= min_dist:
			continue
		if dist > 0.001:
			push += delta.normalized() * (min_dist - dist) * _SEPARATION_STRENGTH
		else:
			# Exactly coincident: distance has no direction to push along.
			# Deterministic by id so two views of the same fight agree,
			# rather than depending on iteration order.
			var angle := float(u.id) * 2.4
			push += Vector2(cos(angle), sin(angle)) * min_dist * _SEPARATION_STRENGTH
	return push.limit_length(u.radius * 1.5)

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

	_draw_concentration_badge(u)

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
	y -= BAR_GAP + Palette.FONT_SIZE_SMALL + _crowding_stagger(u)

	_draw_label_chip(u.display_name, y, Palette.TEXT, Palette.FONT_SIZE_SMALL)

const CROWD_RADIUS := 70.0
const CROWD_STEP := 20.0

## Extra headroom for this unit's name label when another unit is standing
## close enough for the two labels to land on the same spot — found in
## Tools/preview/fight_sheet.png, where "abomination" and "Grunt" overlapped
## illegibly the moment two units clashed in melee, which is exactly the
## moment reading who is who matters most. Deterministic by id (lower id
## never moves, each higher id crowded into the same spot stacks one step
## higher) rather than by draw order, so two views of the same fight agree
## on where a label lands.
func _crowding_stagger(u: CombatUnit) -> float:
	if _state == null:
		return 0.0
	return float(crowd_rank(u, _state.units)) * CROWD_STEP

## Split out for testing, same reasoning as status_tags: how many other
## living units with a lower id are within CROWD_RADIUS of this one.
static func crowd_rank(u: CombatUnit, units: Array) -> int:
	var rank := 0
	for other in units:
		if other.id == u.id or not other.alive:
			continue
		if other.id < u.id and u.position.distance_to(other.position) < CROWD_RADIUS:
			rank += 1
	return rank

## Who is this unit currently after. Answers "why is that side winning" by
## itself, before a single number changes: a target being focused by three
## units at once reads differently from one being ignored.
##
## Issue 15's finding: three units converging on one target looked identical
## to three units standing near each other, and the line itself was too faint
## to trace where several overlapped. A dark outline under the line gives it
## contrast against any background; both colours are existing Palette tokens
## at a different alpha, not new literals.
func _draw_targeting_line(u: CombatUnit) -> void:
	if u.focus_id < 0 or u.current_action == &"":
		return
	var target := _state.unit(u.focus_id)
	if target == null or not target.alive:
		return
	var to_target := target.position - u.position
	draw_line(Vector2.ZERO, to_target, Color(Palette.BACKGROUND, 0.5), 4.5)
	draw_line(Vector2.ZERO, to_target, Palette.FOCUS_LINE, 2.5)

## How many other living units currently have this one as their focus —
## "is this unit under fire from more than one thing at once", which issue 15
## found was completely invisible: a scrum of three attackers on one pawn
## looked identical to three attackers merely standing near it. Split out for
## testing without a live canvas, same reasoning as status_tags.
static func concentration_count(u: CombatUnit, units: Array) -> int:
	var count := 0
	for other in units:
		if other.id == u.id or not other.alive:
			continue
		if other.focus_id == u.id:
			count += 1
	return count

const CONCENTRATION_THRESHOLD := 2

## Only drawn once concentration is actually worth flagging (2+): a badge on
## every unit all the time would be noise, and the issue this answers is
## specifically "three attackers on one pawn read as nothing at all", not
## "who has a target".
func _draw_concentration_badge(u: CombatUnit) -> void:
	if _state == null:
		return
	var count := concentration_count(u, _state.units)
	if count < CONCENTRATION_THRESHOLD:
		return
	var badge_center := Vector2(u.radius * 0.75, -u.radius * 0.75)
	draw_circle(badge_center, 11.0, Palette.HP_LOW)
	var font := ThemeDB.fallback_font
	var text := str(count)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL)
	draw_string(font, badge_center - text_size * 0.5 + Vector2(0.0, text_size.y * 0.75),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT)

## Stunned and out-of-resource both look identical to "idle" on the arena
## otherwise: the unit just doesn't do anything, and a viewer with no access
## to CombatUnit.statuses cannot tell a stalled decision from a disabled one.
func _draw_status_tags(u: CombatUnit) -> void:
	var tags := status_tags(u)
	if tags.is_empty():
		return
	_draw_label_chip(" ".join(tags), u.radius + 14.0, Palette.HP_LOW, Palette.FONT_SIZE_SMALL)

## Renders text centred on its own width with a small backdrop chip behind
## it, rather than a fixed draw width that truncates. Found by rendering a
## real fight through six frames (Tools/ContactSheet.gd): "geysermancer"
## silently lost its last letter at the old fixed width, which reads like a
## data bug rather than a rendering limit, and neighbouring labels overlapped
## illegibly whenever units bunched together mid-fight. Full names never
## truncate now; the chip is what keeps an overlapping label readable rather
## than fixing the overlap itself, which needs real layout space this view
## does not have.
func _draw_label_chip(text: String, baseline_y: float, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2(-text_size.x * 0.5, baseline_y)
	var pad := Vector2(3.0, 2.0)
	var chip := Rect2(pos - Vector2(pad.x, text_size.y), text_size + pad * 2.0)
	draw_rect(chip, Color(Palette.BACKGROUND, 0.65))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

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
