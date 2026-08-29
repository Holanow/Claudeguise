extends Node2D
class_name ArenaFloor


## The ground a fight happens on: a floor filling the play area, a boundary at
## the simulated bounds, a faint grid for a sense of scale, and whatever
## terrain the room carries.

const GRID_SPACING := 60.0
const BOUNDARY_WIDTH := 2.0
const GRID_ALPHA := 0.16
const CENTER_LINE_ALPHA := 0.3

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

## Issue 696: id -> recent draw positions, oldest first, for a shot whose
## action asks for a trail. Pruned in `_draw()` against the live projectile
## list, which self-heals across a new fight without BattleView resetting it.
var _trails: Dictionary = {}

## Issue 749: the mark it trails behind draws at ~24.8px (`AttackFX`'s own
## measurement), and a trail under about a third of that loses to the mark
## sitting on top of it. Widened and lengthened just past that line -- "a
## little trail" on a floor-1 elite, not a comet.
const _TRAIL_LENGTH := 14
const _TRAIL_WIDTH := 9.0

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

	ShieldWall.draw_all(self, units, unit_positions)

	UIArt.draw_border(self, Rect2(Vector2(-hw, -hh), Vector2(hw * 2.0, hh * 2.0)),
		Palette.ARENA_EDGE, BOUNDARY_WIDTH, &"arena")

	var live_ids := {}
	for p in projectiles:
		live_ids[p.id] = true
		_draw_projectile(p, shot_positions.get(p.id, p.position))
	for id in _trails.keys():
		if not live_ids.has(id):
			_trails.erase(id)

## One in-flight shot, shaped and coloured by damage type
## (Scripts/Art/AttackFX.gd, PR #69 sable) instead of the plain dot-with-
## trail this replaces. `Projectile` carries `action_id`, not `damage_type`.
## A shot whose action asks for one (issue 696) gets that trail back, drawn
## from live position history rather than baked -- an aim-line exception.
func _draw_projectile(p, at: Vector2) -> void:
	if p.resolved:
		_trails.erase(p.id)
		return
	if _projectile_has_trail(p):
		AttackFX.draw_trail(self, PackedVector2Array(_update_trail(p.id, at)),
			Palette.damage_color(_projectile_damage_type(p)), _TRAIL_WIDTH)
	AttackFX.draw_projectile(self, at, at - p.origin, _projectile_damage_type(p), _PROJECTILE_RADIUS * 3.0)

## Split from _draw_projectile, same reasoning AttackFX's own geometry
## functions are split from their draw_* wrappers: Godot refuses draw_*
## outside _draw(), so this is the part a test can call directly. Falls
## back to PHYSICAL for an action the registry does not know (mirrors
## UnitView._shape_id's own fallback-to-known-default reasoning) rather
## than failing a whole frame's draw over one bad id.
func _projectile_damage_type(p) -> CG.DamageType:
	var action := ActionLibrary.get_action(p.action_id)
	return action.damage_type if action != null else CG.DamageType.PHYSICAL

func _projectile_has_trail(p) -> bool:
	var action := ActionLibrary.get_action(p.action_id)
	return action != null and action.projectile_trail

## Appends `at` to `id`'s history, capped to `_TRAIL_LENGTH`, and returns it.
func _update_trail(id: int, at: Vector2) -> Array:
	var pts: Array = _trails.get(id, [])
	pts.append(at)
	if pts.size() > _TRAIL_LENGTH:
		pts = pts.slice(pts.size() - _TRAIL_LENGTH, pts.size())
	_trails[id] = pts
	return pts

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
		## Issue 759. No new colour: the same physical-damage token BLEED itself
		## uses, at a pool's own flat unstriped fill.
		Terrain.Kind.BLOOD:
			var blood := Palette.damage_color(CG.DamageType.PHYSICAL)
			blood.a = 0.5
			draw_rect(r, blood)

## The four sides of `c` that face different ground, so a block of cells is
## outlined once round the outside instead of once per cell.
func _draw_cell_edges(c: Vector2i, cell) -> void:
	if cell.kind == Terrain.Kind.HAZARD or cell.kind == Terrain.Kind.WATER or cell.kind == Terrain.Kind.BLOOD:
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
