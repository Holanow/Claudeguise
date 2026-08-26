extends RefCounted
class_name TerrainGrid


## The ground a fight happens on, as cells rather than rectangles. A cell is
## one kind of ground or it is nothing, so overlapping paint is unrepresentable.

## Divides the arena (960 x 540) into 64 x 36 whole cells and divides
## `ArenaFloor.GRID_SPACING` (60) exactly, so the drawn reference grid and the
## simulated one cannot disagree. Chosen off
## `Screenshots/teal_625_pool_cell_sizes.png`: the smallest authored pool is
## `geyser_spout` at radius 25, and it survives as 9 cells here against 4 at
## the 25 issue 625 named and 2 at 30, which is no longer a pool.
const CELL := 15.0

## Which grid a stamp writes to. `FLOOR` is authored and lasts the fight;
## `EFFECTS` is what spells paint and a spell may not erase a wall.
enum Layer { FLOOR, EFFECTS }

## Physics layer bits, matching the `TileSet`'s two physics layers.
const BIT_MOVEMENT := 1
const BIT_SIGHT := 2

## Each cell's collider is grown by this much, so neighbours overlap slightly.
## A ray running exactly along the seam between two cells hits neither
## otherwise, and `y = 0` is a seam every fixture in the suite sits on.
const _CELL_OVERLAP := 0.05

var _cells: Array[Dictionary] = [{}, {}]

var _space: RID = RID()
var _terrain_body: RID = RID()
var _cell_shape: RID = RID()
var _unit_shapes: Dictionary = {}
var _unit_bodies: Dictionary = {}

## Cell -> the shape index in `_terrain_body` that makes it opaque, so a stamp
## that stops blocking sight can take its collider away again.
var _sight_shapes: Dictionary = {}

func _init() -> void:
	_space = PhysicsServer2D.space_create()
	PhysicsServer2D.space_set_active(_space, true)
	_terrain_body = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(_terrain_body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_set_space(_terrain_body, _space)
	_cell_shape = PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(_cell_shape,
		Vector2(CELL * 0.5 + _CELL_OVERLAP, CELL * 0.5 + _CELL_OVERLAP))

## Godot's physics RIDs are not reference counted, so a grid that is collected
## without this leaks a space, a body and every shape it made.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in _unit_bodies.values():
		PhysicsServer2D.free_rid(rid)
	for rid in _unit_shapes.values():
		PhysicsServer2D.free_rid(rid)
	if _terrain_body.is_valid():
		PhysicsServer2D.free_rid(_terrain_body)
	if _cell_shape.is_valid():
		PhysicsServer2D.free_rid(_cell_shape)
	if _space.is_valid():
		PhysicsServer2D.free_rid(_space)

# ---------------------------------------------------------------- coordinates

static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

static func rect_of(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c) * CELL, Vector2(CELL, CELL))

## Every cell whose centre lies inside `r`. Centres rather than any-overlap:
## a stamp then covers the ground it is nearest to, so two abutting stamps
## neither double-cover a cell nor leave a gap between them.
static func cells_in_rect(r: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := cell_of(r.position)
	var hi := cell_of(r.end)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if r.has_point(rect_of(c).get_center()):
				out.append(c)
	return out

## Every cell `r` touches at all. Authored terrain stamps with this rather than
## by cell centres: a wall thinner than a cell covers no centre and would
## vanish, and a wall that is not there is worse than one that grew.
static func cells_overlapping(r: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := cell_of(r.position)
	var hi := cell_of(r.end - Vector2(0.0001, 0.0001))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			out.append(Vector2i(x, y))
	return out

static func cells_in_circle(centre: Vector2, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var box := Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	var lo := cell_of(box.position)
	var hi := cell_of(box.end)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if rect_of(c).get_center().distance_to(centre) <= radius:
				out.append(c)
	return out

# -------------------------------------------------------------------- writing

## What one cell holds. Flat values rather than a reference to an authored
## feature, because a cell outlives the stamp that painted it.
class Cell extends RefCounted:
	var kind: Terrain.Kind = Terrain.Kind.WALL
	var damage_per_tick: int = 0
	var damage_type: CG.DamageType = CG.DamageType.PHYSICAL
	var applies_status: CG.Status = CG.Status.SHIELD
	var applies_status_enabled: bool = false
	var status_duration_ticks: int = 0
	var status_magnitude: float = 0.0
	var move_scale: float = 1.0

	func blocks_movement() -> bool:
		return kind == Terrain.Kind.WALL or kind == Terrain.Kind.PIT

	func blocks_sight() -> bool:
		return kind == Terrain.Kind.WALL or kind == Terrain.Kind.PILLAR

static func cell_from_feature(f) -> Cell:
	var c := Cell.new()
	c.kind = f.kind
	c.damage_per_tick = f.damage_per_tick
	c.damage_type = f.damage_type
	c.applies_status = f.applies_status
	c.applies_status_enabled = f.applies_status_enabled
	c.status_duration_ticks = f.status_duration_ticks
	c.status_magnitude = f.status_magnitude
	return c

## Writes `cell` into every cell of `r` on `layer`. Returns the cells that
## actually changed hands, which is what a caller announcing new ground wants.
func stamp_rect(layer: Layer, r: Rect2, cell: Cell) -> Array[Vector2i]:
	return _write(layer, cells_in_rect(r), cell)

func stamp_circle(layer: Layer, centre: Vector2, radius: float, cell: Cell) -> Array[Vector2i]:
	return _write(layer, cells_in_circle(centre, radius), cell)

func _write(layer: Layer, cells: Array[Vector2i], cell: Cell) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	var grid: Dictionary = _cells[layer]
	for c in cells:
		var was = grid.get(c)
		if was != null and was.kind == cell.kind:
			continue
		grid[c] = cell
		changed.append(c)
		_refresh_collider(c)
	return changed

func clear_cell(layer: Layer, c: Vector2i) -> void:
	if not _cells[layer].erase(c):
		return
	_refresh_collider(c)

func clear_layer(layer: Layer) -> void:
	var cells: Array = _cells[layer].keys()
	_cells[layer].clear()
	for c in cells:
		_refresh_collider(c)

## The effects grid answers first, so a pool painted over a floor tile is what
## a unit standing there is in.
func at(c: Vector2i):
	var e = _cells[Layer.EFFECTS].get(c)
	return e if e != null else _cells[Layer.FLOOR].get(c)

func cells(layer: Layer) -> Dictionary:
	return _cells[layer]

## Every cell a shot cannot pass, in a fixed order. Sorted, because the cover
## search walks this and two runs of the same fight must pick the same spot.
func sight_blocking_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _sight_shapes.keys():
		var cell = at(c)
		if cell != null and cell.blocks_sight():
			out.append(c)
	out.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	return out

## How many cells hold ground of any kind. The successor to counting features:
## issue 554 measured a pool stored 147 times over, and a cell is wet once.
func count() -> int:
	var seen: Dictionary = {}
	for layer in [Layer.FLOOR, Layer.EFFECTS]:
		for c in _cells[layer]:
			seen[c] = true
	return seen.size()

## Every cell holding ground, in a fixed order, so a digest of the ground is
## the same two runs running.
func sorted_cells() -> Array[Vector2i]:
	var seen: Dictionary = {}
	for layer in [Layer.FLOOR, Layer.EFFECTS]:
		for c in _cells[layer]:
			seen[c] = true
	var out: Array[Vector2i] = []
	out.assign(seen.keys())
	out.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	return out

## Every cell of `kind`, either layer, in no particular order.
func cells_of_kind(kind: Terrain.Kind) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for layer in [Layer.FLOOR, Layer.EFFECTS]:
		for c in _cells[layer]:
			var cell = at(c)
			if cell != null and cell.kind == kind and not out.has(c):
				out.append(c)
	return out

## No ground of any kind. Units are not ground, so a grid holding only unit
## bodies is still empty and the callers that skip terrain work still skip it.
func is_empty() -> bool:
	return _cells[Layer.FLOOR].is_empty() and _cells[Layer.EFFECTS].is_empty()

## A grid holding one authored feature array and nothing else, for the level
## editor and for tests: they hold rectangles and want the answer the fight
## would give.
static func from_features(features: Array) -> TerrainGrid:
	var g := TerrainGrid.new()
	g.stamp_features(features)
	return g

## Writes authored rectangles onto the floor. The one bridge from the format a
## room is written in to the one a fight asks.
func stamp_features(features: Array) -> void:
	for f in features:
		_write(Layer.FLOOR, cells_overlapping(f.rect), cell_from_feature(f))

# ------------------------------------------------------------------ colliders

## One shape per opaque cell on the shared terrain body. Shapes are never
## removed by index -- removing shifts every later index -- so a cell that
## stops blocking gets a zero-scaled transform instead.
func _refresh_collider(c: Vector2i) -> void:
	var cell = at(c)
	var opaque: bool = cell != null and cell.blocks_sight()
	if _sight_shapes.has(c):
		var idx: int = _sight_shapes[c]
		PhysicsServer2D.body_set_shape_disabled(_terrain_body, idx, not opaque)
		return
	if not opaque:
		return
	var idx := PhysicsServer2D.body_get_shape_count(_terrain_body)
	PhysicsServer2D.body_add_shape(_terrain_body, _cell_shape)
	PhysicsServer2D.body_set_shape_transform(_terrain_body, idx,
		Transform2D(0.0, rect_of(c).get_center()))
	## After the shape, never before. A collision layer set on a body with no
	## shapes does not reach the broadphase, and the body is then invisible to
	## every masked query for the rest of its life.
	PhysicsServer2D.body_set_collision_layer(_terrain_body, BIT_SIGHT)
	_sight_shapes[c] = idx

## Issue 625, the player's ruling: a unit's own body blocks line of sight, so a
## melee line in front of casters protects them. Called once per tick, before
## anything decides; a unit that died since the last call loses its body here.
func sync_units(units: Array) -> void:
	for u in units:
		if not u.alive:
			_drop_unit(u.id)
			continue
		if not _unit_bodies.has(u.id):
			_make_unit(u.id, u.radius)
		PhysicsServer2D.body_set_state(_unit_bodies[u.id],
			PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, u.position))

func _make_unit(id: int, radius: float) -> void:
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, radius)
	var body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_set_space(body, _space)
	PhysicsServer2D.body_add_shape(body, shape)
	PhysicsServer2D.body_set_collision_layer(body, BIT_SIGHT)
	_unit_shapes[id] = shape
	_unit_bodies[id] = body

func _drop_unit(id: int) -> void:
	if not _unit_bodies.has(id):
		return
	PhysicsServer2D.free_rid(_unit_bodies[id])
	PhysicsServer2D.free_rid(_unit_shapes[id])
	_unit_bodies.erase(id)
	_unit_shapes.erase(id)

func unit_body(id: int) -> RID:
	return _unit_bodies.get(id, RID())

# ------------------------------------------------------------------- querying

## True when nothing opaque stands between `a` and `b`. The ray is masked to
## the sight layer, so the first hit means blocked and nothing is re-cast.
## `ignore` are the shooter and the intended target: excluding the shooter
## stops every unit blocking itself, and excluding the target makes hitting it
## success rather than obstruction.
func sight_blocked(a: Vector2, b: Vector2, ignore: Array[int] = []) -> bool:
	if a.is_equal_approx(b):
		return false
	## Ground a unit can stand in hides it from outside but not from someone
	## standing in it with them. A wall is not that: nothing stands in a wall,
	## so it blocks however it contains the line.
	var ca = at(cell_of(a))
	var cb = at(cell_of(b))
	if ca != null and cb != null and ca.blocks_sight() and not ca.blocks_movement() 			and cb.blocks_sight() and not cb.blocks_movement():
		return false
	var st := PhysicsServer2D.space_get_direct_state(_space)
	if st == null:
		return false
	var q := PhysicsRayQueryParameters2D.create(a, b)
	q.collision_mask = BIT_SIGHT
	q.collide_with_areas = false
	## A unit standing inside a pillar is hidden by it, which is what the float
	## geometry did and what `test_combat_sightline_endpoints` asserts. Without
	## this a ray starting inside a shape reports no hit at all.
	q.hit_from_inside = true
	var excluded: Array[RID] = []
	for id in ignore:
		var rid: RID = _unit_bodies.get(id, RID())
		if rid.is_valid():
			excluded.append(rid)
	q.exclude = excluded
	return not st.intersect_ray(q).is_empty()

## True when a body of `radius` centred at `p` overlaps ground it cannot enter.
## Grid arithmetic rather than a physics query: movement asks this several
## times per unit per tick and it needs no colliders to answer.
func move_blocked(p: Vector2, radius: float) -> bool:
	for c in cells_overlapping(Rect2(p - Vector2(radius, radius), Vector2(radius, radius) * 2.0)):
		var cell = at(c)
		if cell == null or not cell.blocks_movement():
			continue
		var r := rect_of(c)
		var nearest := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		if nearest.distance_to(p) <= radius:
			return true
	return false

## The harmful ground under `p`, as zero or one cell. A cell is one kind of
## ground, so the array that used to come back from overlapping rectangles
## can now hold at most one thing.
func hazards_at(p: Vector2) -> Array:
	var cell = at(cell_of(p))
	if cell != null and cell.kind == Terrain.Kind.HAZARD:
		return [cell]
	return []

func cell_at(p: Vector2):
	return at(cell_of(p))
