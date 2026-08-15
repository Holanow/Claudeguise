extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const StatusIcons := preload("res://Scripts/Art/StatusIcons.gd")
const ActionIcons := preload("res://Scripts/Art/ActionIcons.gd")
const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")

## Draws status badges and wind-up icons over the real battle screen, for
## Tools/IconsInFight.gd. A preview harness, not the shipped placement -- the
## header of that file says so at length and it is the important caveat.
##
## Reads `Scripts/UI/UnitView.gd` for its constants so the badges sit where the
## real ones would rather than where I guessed. Reading is not editing.
##
## **That claim used to be false about SIZE and it mattered.** `BADGE` and `ICON`
## were hardcoded at 14.0 and 16.0 raw screen pixels, while the shipped ones are
## world-space values scaled by the arena fit -- 17.4 px and 19.9 px at 1280x720.
## So this harness drew every badge about 20% SMALLER than the game does, and
## every judgement anyone made about these badges, including a fresh-eyes
## playtest that called them "invisible at 1x", was made on the wrong number.
##
## The comment two lines up was already there and already said the right
## intention. The intention was not derived, which is this project's most
## expensive recurring failure: a measurement aimed one degree off.
##
## They are functions now rather than constants, because the answer depends on
## the arena's scale and a constant cannot.

const BAR_W := 34.0
const BAR_H := 5.0

## Gap between the unit's own drawn edge and this overlay, in world units.
##
## The first render anchored off the top of UnitView's whole name/HP/resource
## stack instead, and put every badge above the arena rectangle entirely, in the
## HUD. Anchoring on the unit's own radius keeps them on the unit at any arena
## zoom, which is what a badge has to do.
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

func _draw_badges(u, cx: float, y: float) -> void:
	var list: Array = u.statuses.keys()
	if list.is_empty():
		return
	# Harmful first so a fight full of buffs never pushes the thing that is
	# killing you off the end of the row.
	list.sort_custom(func(a, b): return CG.is_harmful(a) and not CG.is_harmful(b))
	var badge := badge_px(arena.transform.get_scale().x)
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

## The size the SHIPPED badge occupies on screen, given the arena's scale.
## Static so a test can check the harness against the game without a live scene.
static func badge_px(arena_scale: float) -> float:
	return UnitViewScript.STATUS_BADGE_SIZE * arena_scale

static func icon_px(arena_scale: float) -> float:
	return UnitViewScript.WIND_UP_ICON_SIZE * arena_scale
