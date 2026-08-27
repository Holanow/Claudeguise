extends Node2D
class_name ArenaFloor


## The ground a fight happens on: a floor filling the play area, a boundary at
## the simulated bounds, a faint grid for a sense of scale, and whatever
## terrain the room carries.

const GRID_SPACING := 60.0
const BOUNDARY_WIDTH := 2.0
const GRID_ALPHA := 0.16
const CENTER_LINE_ALPHA := 0.3

## Set by the level editor, which authors rectangles. A fight sets `grid`
## instead; whichever is set is what gets drawn.
var terrain: Array = []

## Set by BattleView from CombatState.grid, once, and mutated in place after.
var grid: TerrainGrid = null

## Set by BattleView from CombatState.projectiles every stepped tick.
var projectiles: Array = []

## Issue 501: projectile id -> where that shot is drawn this frame, between the
## tick it left and the tick it is on. An id with no entry draws from state.
var shot_positions: Dictionary = {}

## Set by BattleView from CombatState.units every stepped tick, for the cover a
## shielder holds: it is drawn here, on the parent of every UnitView, so it
## cannot repaint the units standing behind it (issue 332).
var units: Array = []

## Issue 511: unit id -> where that body is drawn this frame. The plate a
## shielder holds is anchored to it, so cover stays on the arm holding it
## between ticks. An id with no entry draws from state.
var unit_positions: Dictionary = {}

const _PROJECTILE_RADIUS := 5.0

func _draw() -> void:
	var hw := CG.ARENA_HALF_WIDTH
	var hh := CG.ARENA_HALF_HEIGHT

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

	if grid != null:
		_draw_grid()
	else:
		for feature in terrain:
			_draw_feature(feature)

	ShieldWall.draw_all(self, units, UnitView.DISPLAY_SCALE, unit_positions)

	UIArt.draw_border(self, Rect2(Vector2(-hw, -hh), Vector2(hw * 2.0, hh * 2.0)),
		Palette.ARENA_EDGE, BOUNDARY_WIDTH, &"arena")

	for p in projectiles:
		_draw_projectile(p, shot_positions.get(p.id, p.position))

## One in-flight shot, shaped and coloured by damage type
## (Scripts/Art/AttackFX.gd, PR #69 sable) instead of the plain dot-with-
## trail this replaces. `Projectile` carries `action_id`, not `damage_type`
func _draw_projectile(p, at: Vector2) -> void:
	if p.resolved:
		return
	AttackFX.draw_projectile(self, at, at - p.origin, _projectile_damage_type(p), _PROJECTILE_RADIUS * 3.0)

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
func _draw_feature(feature) -> void:
	match feature.kind:
		Terrain.Kind.WALL:
			draw_rect(feature.rect, Palette.ARENA_EDGE)
			draw_rect(feature.rect, Palette.TEXT_DIM, false, 2.0)
		Terrain.Kind.PILLAR:
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
		## Issue 492. Flat and unstriped on purpose: a hazard's stripes say "do
		## not stand here" and a pool is the one piece of ground that is safe.
		Terrain.Kind.WATER:
			var water := Palette.damage_color(CG.DamageType.WATER)
			water.a = 0.45
			draw_rect(feature.rect, water)

## Issue 625: the ground as cells. Cells of one kind sit flush and read as one
## shape, so only the edges where the kind changes get an outline -- filling
## and outlining every cell drew a chessboard.
func _draw_grid() -> void:
	var seen: Dictionary = {}
	for layer in [TerrainGrid.Layer.FLOOR, TerrainGrid.Layer.EFFECTS]:
		for c in grid.cells(layer).keys():
			if seen.has(c):
				continue
			seen[c] = true
	var cells: Array = seen.keys()
	cells.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	for c in cells:
		_draw_cell(c, grid.at(c))
	for c in cells:
		_draw_cell_edges(c, grid.at(c))

func _draw_cell(c: Vector2i, cell) -> void:
	var r := TerrainGrid.rect_of(c)
	match cell.kind:
		Terrain.Kind.WALL, Terrain.Kind.PILLAR:
			draw_rect(r, Palette.ARENA_EDGE)
		Terrain.Kind.PIT:
			draw_rect(r, Palette.BACKGROUND)
		Terrain.Kind.HAZARD:
			var color := Palette.damage_color(cell.damage_type)
			color.a = 0.35
			draw_rect(r, color)
			_draw_hazard_stripes(r, color)
		Terrain.Kind.WATER:
			var water := Palette.damage_color(CG.DamageType.WATER)
			water.a = 0.45
			draw_rect(r, water)

## The four sides of `c` that face different ground, so a block of cells is
## outlined once round the outside instead of once per cell.
func _draw_cell_edges(c: Vector2i, cell) -> void:
	if cell.kind == Terrain.Kind.HAZARD or cell.kind == Terrain.Kind.WATER:
		return
	var color := Palette.TEXT_DIM if cell.kind != Terrain.Kind.PIT else Palette.ARENA_EDGE
	var r := TerrainGrid.rect_of(c)
	var sides := [
		[Vector2i(0, -1), r.position, Vector2(r.end.x, r.position.y)],
		[Vector2i(0, 1), Vector2(r.position.x, r.end.y), r.end],
		[Vector2i(-1, 0), r.position, Vector2(r.position.x, r.end.y)],
		[Vector2i(1, 0), Vector2(r.end.x, r.position.y), r.end],
	]
	for side in sides:
		var other = grid.at(c + side[0])
		if other != null and other.kind == cell.kind:
			continue
		draw_line(side[1], side[2], color, 2.0)

const _HAZARD_STRIPE_SPACING := 20.0

## Diagonal warning stripes, the same visual grammar as a hazard tile in most
## games: passable, but the floor itself is telling you not to stand there.
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
