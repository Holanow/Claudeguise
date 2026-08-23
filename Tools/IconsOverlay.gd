extends Node2D
class_name IconsOverlay

const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")

## Badge and wind-up icon geometry, kept apart from the shipped placement.
## Nothing launches this: `Tests/test_art.gd` reads its static measurements, and
## `Tools/IconsInFight.gd`, the harness it was drawn for, no longer exists.

const BAR_W := 34.0
const BAR_H := 5.0

## Gap between the unit's own drawn edge and this overlay, in world units.
const GAP := 8.0

var arena: Node2D = null
var battle: Node = null
var state = null

func afflicted_count() -> int:
	if state == null:
		return 0
	var n := 0
	for u in state.units:
		if u.alive and not u.statuses.is_empty():
			n += 1
	return n

func _draw() -> void:
	if state == null or arena == null:
		return
	var xform := arena.transform
	var s: float = xform.get_scale().x
	for u in state.units:
		if not u.alive:
			continue
		var center: Vector2 = xform * u.position
		var edge := (UnitViewScript.display_radius(u) + GAP) * s
		# Wind-up above, statuses below. Above is where the wind-up ring already
		# is, and below is where the status *text* already is -- badges are
		# meant to replace that text, so this is where they belong.
		_draw_wind_up(u, center.x, center.y - edge)
		_draw_badges(u, center.x, center.y + edge)

## The same mapping `UnitView._shape_id` makes: a pawn draws its class, an enemy
## draws its enemy id. Duplicated here rather than reached for because the one in
## `UnitView` is an instance method on a node this overlay does not have.
static func _shape_id(u) -> StringName:
	if u.pawn != null and u.pawn.pawn_class != null:
		return u.pawn.pawn_class.id
	return u.enemy_id

func _draw_badges(u, cx: float, y: float) -> void:
	var list: Array = u.statuses.keys()
	if list.is_empty():
		return
	# Harmful first so a fight full of buffs never pushes the thing that is
	# killing you off the end of the row.
	list.sort_custom(func(a, b): return CG.is_harmful(a) and not CG.is_harmful(b))
	var badge := badge_px(_shape_id(u), u.team, UnitViewScript.display_radius(u), arena.transform.get_scale().x)
	var width := StatusIcons.row_width(list.size(), badge)
	var rects := StatusIcons.layout_row(Vector2(cx - width * 0.5, y), list.size(), badge)
	for i in list.size():
		StatusIcons.draw_status(self, list[i], rects[i])

func _draw_wind_up(u, cx: float, y: float) -> void:
	if u.current_action == &"" or u.action_ticks_total <= 0:
		return
	var action = Registry.get_action(u.current_action)
	if action == null:
		return
	var progress := clampf(float(u.action_ticks_total - u.action_ticks_left) / float(u.action_ticks_total), 0.0, 1.0)
	var icon := icon_px(arena.transform.get_scale().x)
	var total := BAR_W + 4.0 + icon
	var x := cx - total * 0.5
	var color := Palette.damage_color(action.damage_type)
	draw_rect(Rect2(x, y - BAR_H, BAR_W, BAR_H), Palette.HP_BACK)
	draw_rect(Rect2(x, y - BAR_H, BAR_W * progress, BAR_H), color)
	ActionIcons.draw_action(self, u.current_action, action.damage_type, Rect2(x + BAR_W + 4.0, y - icon, icon, icon))

## The size the SHIPPED badge occupies on screen, for THIS unit, given the
## arena's scale. Static so a test can check the harness against the game
## without a live scene.
static func badge_px(shape_id: StringName, team: CG.Team, radius: float, arena_scale: float) -> float:
	return UnitViewScript.status_badge_size(shape_id, team, radius) * arena_scale

static func icon_px(arena_scale: float) -> float:
	return UnitViewScript.WIND_UP_ICON_SIZE * arena_scale
