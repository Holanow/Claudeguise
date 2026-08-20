extends Node2D
class_name ArenaFloor


## The ground a fight happens on: a floor filling the play area, a boundary at
## the simulated bounds, a faint grid for a sense of scale, and whatever
## terrain the room carries.
##
## OWNER: pike.
##
## Attached to the Arena node itself, so it is drawn in the same local space
## that _layout_arena positions and scales â€” the drawn rectangle is
## CG.ARENA_HALF_WIDTH/HEIGHT, the same constants the simulation places units
## within, not a second guess at the same numbers. Terrain rects arrive in the
## same space for the same reason: BattleView hands over CombatState.terrain
## directly, not a converted copy.
##
## Kept quieter than the units on purpose: low alpha on the grid and centre
## lines, and the boundary is a thin outline rather than a filled shape.

const GRID_SPACING := 60.0
const BOUNDARY_WIDTH := 2.0
const GRID_ALPHA := 0.16
const CENTER_LINE_ALPHA := 0.3

## Set by BattleView from CombatState.terrain (Terrain.Feature, untyped Array
## per Terrain.gd's own contract). Empty by default, so a screen built before
## a fight exists (or against a fixture with no terrain) draws nothing extra.
var terrain: Array = []

## Set by BattleView from CombatState.projectiles every stepped tick.
## PLAYTEST-NOTES 2: "I'm still seeing beams and not projectiles" â€” issue 18
## gave every ranged action a real travelling shot with a per-tick position,
## and nothing drew it; UnitView kept drawing an instant source-to-target
## line for the whole action instead. UnitView now suppresses that line once
## a shot is actually in flight (see its _has_active_projectile), and this is
## the shot itself: a small marker at the projectile's live position, not
## the full path, so a slow shot visibly lags behind a fast one instead of
## both reading as the same instant line.
var projectiles: Array = []

const _PROJECTILE_RADIUS := 5.0

func _draw() -> void:
	var hw := CG.ARENA_HALF_WIDTH
	var hh := CG.ARENA_HALF_HEIGHT

	# Issue 237. `Assets/UI/README.md` has promised the player an
	UIArt.draw_background(self, Rect2(Vector2(-hw, -hh), Vector2(hw * 2.0, hh * 2.0)),
		&"arena", Palette.ARENA_FLOOR)

	var grid_color := Palette.ARENA_EDGE
	grid_color.a = GRID_ALPHA
	var gx := -hw
	while gx <= hw:
		draw_line(Vector2(gx, -hh), Vector2(gx, hh), grid_color, 1.0)
		gx += GRID_SPACING
	var gy := -hh
	while gy <= hh:
		draw_line(Vector2(-hw, gy), Vector2(hw, gy), grid_color, 1.0)
		gy += GRID_SPACING

	var center_color := Palette.ARENA_EDGE
	center_color.a = CENTER_LINE_ALPHA
	draw_line(Vector2(-hw, 0.0), Vector2(hw, 0.0), center_color, 1.0)
	draw_line(Vector2(0.0, -hh), Vector2(0.0, hh), center_color, 1.0)

	for feature in terrain:
		_draw_feature(feature)

	# The frame around the arena, through the same drop-in pipeline as the
	UIArt.draw_border(self, Rect2(Vector2(-hw, -hh), Vector2(hw * 2.0, hh * 2.0)),
		Palette.ARENA_EDGE, BOUNDARY_WIDTH, &"arena")

	for p in projectiles:
		_draw_projectile(p)

## One in-flight shot, shaped and coloured by damage type
## (Scripts/Art/AttackFX.gd, PR #69 sable) instead of the plain dot-with-
## trail this replaces. `Projectile` carries `action_id`, not `damage_type`
## -- sable flagged this as the one open question their signature proposal
## couldn't answer from Scripts/Art, and a `Registry.get_action` lookup from
## here was the cheaper of the two options they posted (the other being a
## new field on `Projectile` itself, Core, at spawn time). `Registry` is
## already reachable from Scripts/UI elsewhere (PartySelect, InspectPanel),
## so no Core change needed for this piece. Resolved shots are skipped --
## BattleView hands over the live array every tick and a resolved entry
## stays in place per Projectile.gd's own append-only contract, so this is
## the filter that keeps a spent shot from drawing forever at its landing
## point.
func _draw_projectile(p) -> void:
	if p.resolved:
		return
	AttackFX.draw_projectile(self, p.position, p.position - p.origin, _projectile_damage_type(p), _PROJECTILE_RADIUS * 3.0)

## Split from _draw_projectile, same reasoning AttackFX's own geometry
## functions are split from their draw_* wrappers: Godot refuses draw_*
## outside _draw(), so this is the part a test can call directly. Falls
## back to PHYSICAL for an action the registry does not know (mirrors
## UnitView._shape_id's own fallback-to-known-default reasoning) rather
## than failing a whole frame's draw over one bad id.
func _projectile_damage_type(p) -> CG.DamageType:
	var action := Registry.get_action(p.action_id)
	return action.damage_type if action != null else CG.DamageType.PHYSICAL

## Four kinds, two axes (blocks movement / blocks sight), and no new Palette
## colours: everything below reuses tokens that already exist, distinguished
## by fill, footprint and pattern rather than a fifth colour nobody asked for.
##
## Issue 26's own requirement, quoted directly: "a pit must not look like a
## wall â€” they behave like exact opposites, one blocking movement and not
## sight, the other the reverse." Wall is drawn as solid mass filling its
## whole rect (blocks both). Pit is drawn as its opposite: a dark void with
## only an edge, no fill, reading as "an absence" rather than "an object" â€”
## you can see clean over it, you cannot walk into it.
func _draw_feature(feature) -> void:
	match feature.kind:
		Terrain.Kind.WALL:
			draw_rect(feature.rect, Palette.ARENA_EDGE)
			draw_rect(feature.rect, Palette.TEXT_DIM, false, 2.0)
		Terrain.Kind.PILLAR:
			# A column, not a span: drawn as a circle inscribed in its rect
			var center: Vector2 = feature.rect.get_center()
			var radius: float = min(feature.rect.size.x, feature.rect.size.y) * 0.5
			draw_circle(center, radius, Palette.ARENA_EDGE)
			draw_arc(center, radius, 0.0, TAU, 24, Palette.TEXT_DIM, 2.0, true)
		Terrain.Kind.HAZARD:
			var color := Palette.damage_color(feature.damage_type)
			color.a = 0.35
			draw_rect(feature.rect, color)
			_draw_hazard_stripes(feature.rect, color)
		Terrain.Kind.PIT:
			draw_rect(feature.rect, Palette.BACKGROUND)
			draw_rect(feature.rect, Palette.ARENA_EDGE, false, 2.0)

const _HAZARD_STRIPE_SPACING := 20.0

## Diagonal warning stripes, the same visual grammar as a hazard tile in most
## games: passable, but the floor itself is telling you not to stand there.
##
## Each stripe is the line from (t, 0) sliding down the top-then-right edge
## to (0, t) sliding down the left-then-bottom edge, independently clamped
## to the rect's own size on each axis â€” the standard diagonal-hatch-in-a-
## rect construction. An earlier version clamped two Vector2 *parameters* in
## a helper function and never used the clamped result, since GDScript
## passes Vector2 by value: the caller kept drawing with the original,
## unclamped points, so a stripe on a wide short rect drew mostly outside
## it. No helper now â€” clamped directly at the call site.
func _draw_hazard_stripes(rect: Rect2, base_color: Color) -> void:
	var stripe_color := base_color
	stripe_color.a = minf(base_color.a * 1.6, 0.7)
	var span := rect.size.x + rect.size.y
	var t := 0.0
	while t < span:
		var p1 := Vector2(clampf(t, 0.0, rect.size.x), maxf(0.0, t - rect.size.x))
		var p2 := Vector2(maxf(0.0, t - rect.size.y), clampf(t, 0.0, rect.size.y))
		if p1 != p2:
			draw_line(rect.position + p1, rect.position + p2, stripe_color, 1.5)
		t += _HAZARD_STRIPE_SPACING
