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

const _FLUID_SHADER := preload("res://Shaders/Terrain/fluid.gdshader")

## Issue 760: a fluid surface moves, so it is a ShaderMaterial rather than a
## fill, and a material belongs to a whole CanvasItem. So the ground and each
## fluid draw on their own children, ordered by `z_index` rather than by tree
## order -- `BattleView._rebuild_units` frees every child of this node at the
## start of a fight, so which order they come back in is not ours to pick.
class ArenaLayer extends Node2D:
	var arena = null
	## A `Terrain.Kind` for a fluid, or -1 for the ground under both.
	var kind: int = -1

	func _draw() -> void:
		if arena == null:
			return
		if kind < 0:
			arena.draw_ground(self)
		else:
			arena.draw_fluid(self, kind)

var _ground_layer: Node2D = null
var _water_layer: Node2D = null
var _blood_layer: Node2D = null

func _ready() -> void:
	_ensure_layers()

## Self-healing, because `_rebuild_units` takes all three away again on every
## `begin`. One frame of bare arena on a restart is the cost.
func _process(_delta: float) -> void:
	if not is_instance_valid(_ground_layer):
		_ensure_layers()

func _ensure_layers() -> void:
	if is_instance_valid(_ground_layer):
		return
	_ground_layer = _make_layer(-1, -3)
	_water_layer = _make_layer(Terrain.Kind.WATER, -2)
	_blood_layer = _make_layer(Terrain.Kind.BLOOD, -2)
	_water_layer.material = _fluid_material(
		Palette.damage_color(CG.DamageType.WATER), 0.45, 1.0, 0.055)
	## Issue 855: its own red, not the physical-damage token, because moving
	## grey read as smoke. Still the thicker, slower, tighter of the two.
	_blood_layer.material = _fluid_material(
		Palette.ARENA_BLOOD, 0.55, 0.4, 0.085)
	for layer in [_ground_layer, _water_layer, _blood_layer]:
		add_child(layer)

func _make_layer(kind: int, z: int) -> Node2D:
	var layer := ArenaLayer.new()
	layer.arena = self
	layer.kind = kind
	layer.z_index = z
	return layer

## Water is bright, quick and wide; blood is dark, slow and tight. One shader,
## and the whole difference between the two fluids is these four numbers.
func _fluid_material(tint: Color, alpha: float, speed: float, scale: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _FLUID_SHADER
	mat.set_shader_parameter(&"tint", tint)
	mat.set_shader_parameter(&"base_alpha", alpha)
	mat.set_shader_parameter(&"speed", speed)
	mat.set_shader_parameter(&"ripple_scale", scale)
	return mat

func _draw() -> void:
	var hw := CG.ARENA_HALF_WIDTH
	var hh := CG.ARENA_HALF_HEIGHT

	ShieldWall.draw_all(self, units, unit_positions)

	UIArt.draw_border(self, Rect2(Vector2(-hw, -hh), Vector2(hw * 2.0, hh * 2.0)),
		Palette.ARENA_EDGE, BOUNDARY_WIDTH, &"arena")

	var live_ids := {}
	for p in projectiles:
		live_ids[p.id] = true
		_draw_projectile(self, p, shot_positions.get(p.id, p.position))
	for id in _trails.keys():
		if not live_ids.has(id):
			_trails.erase(id)

	for layer in [_ground_layer, _water_layer, _blood_layer]:
		if is_instance_valid(layer):
			layer.queue_redraw()

## The floor, the reference grid and every cell that is not a fluid, drawn
## under both pools.
func draw_ground(target: Node2D) -> void:
	var hw := CG.ARENA_HALF_WIDTH
	var hh := CG.ARENA_HALF_HEIGHT

	UIArt.draw_background(target, Rect2(Vector2(-hw, -hh), Vector2(hw * 2.0, hh * 2.0)),
		&"arena", Palette.ARENA_FLOOR)

	var grid_color := Palette.ARENA_EDGE
	grid_color.a = GRID_ALPHA
	var gx := -hw
	while gx <= hw:
		target.draw_line(Vector2(gx, -hh), Vector2(gx, hh), grid_color, 1.0)
		gx += GRID_SPACING
	var gy := -hh
	while gy <= hh:
		target.draw_line(Vector2(-hw, gy), Vector2(hw, gy), grid_color, 1.0)
		gy += GRID_SPACING

	var center_color := Palette.ARENA_EDGE
	center_color.a = CENTER_LINE_ALPHA
	target.draw_line(Vector2(-hw, 0.0), Vector2(hw, 0.0), center_color, 1.0)
	target.draw_line(Vector2(0.0, -hh), Vector2(0.0, hh), center_color, 1.0)

	if grid != null:
		_draw_grid(target)

## Every cell of one fluid, each carrying which of its four sides face other
## ground in `r,g,b,a` = left, right, top, bottom. That is what lets the shader
## soften a pool's outline without eroding the seams inside it.
func draw_fluid(target: Node2D, kind: int) -> void:
	if grid == null:
		return
	for c in grid.cells_of_kind(kind):
		target.draw_rect(TerrainGrid.rect_of(c), fluid_edge_flags(c, kind))

## Split out for the same reason `_projectile_damage_type` is: Godot refuses
## `draw_*` outside `_draw`, so this is the part a test can call directly.
func fluid_edge_flags(c: Vector2i, kind: int) -> Color:
	return Color(
		0.0 if _same_kind(c + Vector2i(-1, 0), kind) else 1.0,
		0.0 if _same_kind(c + Vector2i(1, 0), kind) else 1.0,
		0.0 if _same_kind(c + Vector2i(0, -1), kind) else 1.0,
		0.0 if _same_kind(c + Vector2i(0, 1), kind) else 1.0)

func _same_kind(c: Vector2i, kind: int) -> bool:
	var other = grid.at(c)
	return other != null and other.kind == kind

## One in-flight shot, shaped and coloured by damage type
## (Scripts/Art/AttackFX.gd, PR #69 sable) instead of the plain dot-with-
## trail this replaces. `Projectile` carries `action_id`, not `damage_type`.
## A shot whose action asks for one (issue 696) gets that trail back, drawn
## from live position history rather than baked -- an aim-line exception.
func _draw_projectile(target: Node2D, p, at: Vector2) -> void:
	if p.resolved:
		_trails.erase(p.id)
		return
	if _projectile_has_trail(p):
		AttackFX.draw_trail(target, PackedVector2Array(_update_trail(p.id, at)),
			Palette.damage_color(_projectile_damage_type(p)), _TRAIL_WIDTH)
	AttackFX.draw_projectile(target, at, at - p.origin, _projectile_damage_type(p), _PROJECTILE_RADIUS * 3.0)

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
func _draw_grid(target: Node2D) -> void:
	var seen: Dictionary = {}
	for layer in [TerrainGrid.Layer.FLOOR, TerrainGrid.Layer.EFFECTS]:
		for c in grid.cells(layer).keys():
			if seen.has(c):
				continue
			seen[c] = true
	var cells: Array = seen.keys()
	cells.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	for c in cells:
		_draw_cell(target, c, grid.at(c))
	for c in cells:
		_draw_cell_edges(target, c, grid.at(c))

func _draw_cell(target: Node2D, c: Vector2i, cell) -> void:
	var r := TerrainGrid.rect_of(c)
	match cell.kind:
		Terrain.Kind.WALL, Terrain.Kind.PILLAR:
			target.draw_rect(r, Palette.ARENA_EDGE)
		Terrain.Kind.PIT:
			target.draw_rect(r, Palette.BACKGROUND)
		Terrain.Kind.HAZARD:
			var color := Palette.damage_color(cell.damage_type)
			color.a = 0.35
			target.draw_rect(r, color)
			_draw_hazard_stripes(target, r, color)

## The four sides of `c` that face different ground, so a block of cells is
## outlined once round the outside instead of once per cell.
func _draw_cell_edges(target: Node2D, c: Vector2i, cell) -> void:
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
		target.draw_line(side[1], side[2], color, 2.0)

const _HAZARD_STRIPE_SPACING := 20.0

## Diagonal warning stripes, the same visual grammar as a hazard tile in most
## games: passable, but the floor itself is telling you not to stand there.
func _draw_hazard_stripes(target: Node2D, rect: Rect2, base_color: Color) -> void:
	var stripe_color := base_color
	stripe_color.a = minf(base_color.a * 1.6, 0.7)
	var span := rect.size.x + rect.size.y
	var t := 0.0
	while t < span:
		var p1 := Vector2(clampf(t, 0.0, rect.size.x), maxf(0.0, t - rect.size.x))
		var p2 := Vector2(maxf(0.0, t - rect.size.y), clampf(t, 0.0, rect.size.y))
		if p1 != p2:
			target.draw_line(rect.position + p1, rect.position + p2, stripe_color, 1.5)
		t += _HAZARD_STRIPE_SPACING
