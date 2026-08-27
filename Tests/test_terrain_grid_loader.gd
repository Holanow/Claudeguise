extends "res://Tests/TestCase.gd"


## Issue #680 step 2: a hand-built `TileMapLayer` must produce the grid the
## equivalent rectangle produces, field by field -- not just "loads without
## erroring". `ResourceSaver` silently dropping data is the third trap this
## project has found (#633, #668), so this compares the loaded object rather
## than trusting the load succeeded.

const _TILESET_PATH := "res://Assets/Terrain/arena_tileset.tres"

## Atlas coordinates from `Tools/GenerateArenaTileset.gd`'s own tile order.
const _WALL := Vector2i(0, 0)
const _PILLAR := Vector2i(1, 0)
const _PIT := Vector2i(2, 0)
const _WATER := Vector2i(3, 0)
const _HAZARD_FIRE := Vector2i(4, 0)
const _HAZARD_SLOW := Vector2i(5, 0)

func _layer_with(cells: Dictionary) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = load(_TILESET_PATH)
	for coord in cells:
		layer.set_cell(coord, 0, cells[coord])
	return layer

func _paint(atlas_coord: Vector2i, rect: Rect2) -> Dictionary:
	var out := {}
	for c in TerrainGrid.authored_cells(rect):
		out[c] = atlas_coord
	return out

func _assert_cell_eq(got, want, at: Vector2i) -> void:
	assert_not_null(got, "cell missing at %s" % [at])
	assert_eq(got.kind, want.kind, "kind at %s" % [at])
	assert_eq(got.damage_per_tick, want.damage_per_tick, "damage_per_tick at %s" % [at])
	assert_eq(got.damage_type, want.damage_type, "damage_type at %s" % [at])
	assert_eq(got.applies_status, want.applies_status, "applies_status at %s" % [at])
	assert_eq(got.applies_status_enabled, want.applies_status_enabled, "applies_status_enabled at %s" % [at])
	assert_eq(got.status_duration_ticks, want.status_duration_ticks, "status_duration_ticks at %s" % [at])
	assert_almost_eq(got.status_magnitude, want.status_magnitude, 0.0001, "status_magnitude at %s" % [at])
	assert_almost_eq(got.move_scale, want.move_scale, 0.0001, "move_scale at %s" % [at])

func _assert_grids_match(layer: TileMapLayer, features: Array) -> void:
	var loaded := TerrainGridLoader.grid_from_layer(layer)
	var built := TerrainGrid.from_features(features)
	assert_eq(loaded.sorted_cells(), built.sorted_cells(), "cell set")
	for c in built.sorted_cells():
		_assert_cell_eq(loaded.at(c), built.at(c), c)

func test_a_wall_matches_the_rectangle_it_replaces() -> void:
	var rect := Rect2(-30.0, -30.0, 60.0, 60.0)
	var layer := _layer_with(_paint(_WALL, rect))
	_assert_grids_match(layer, [Terrain.make(Terrain.Kind.WALL, rect)])

func test_a_pillar_matches_the_rectangle_it_replaces() -> void:
	var rect := Rect2(-100.0, -250.0, 100.0, 100.0)
	var layer := _layer_with(_paint(_PILLAR, rect))
	_assert_grids_match(layer, [Terrain.make(Terrain.Kind.PILLAR, rect)])

func test_a_pit_matches_the_rectangle_it_replaces() -> void:
	var rect := Rect2(-20.0, -270.0, 60.0, 210.0)
	var layer := _layer_with(_paint(_PIT, rect))
	_assert_grids_match(layer, [Terrain.make(Terrain.Kind.PIT, rect)])

func test_a_water_pool_matches_the_rectangle_it_replaces() -> void:
	var rect := Rect2(0.0, 0.0, 45.0, 45.0)
	var layer := _layer_with(_paint(_WATER, rect))
	_assert_grids_match(layer, [Terrain.pool(rect)])

func test_a_fire_hazard_matches_the_rectangle_it_replaces() -> void:
	var rect := Rect2(-80.0, -110.0, 200.0, 220.0)
	var layer := _layer_with(_paint(_HAZARD_FIRE, rect))
	_assert_grids_match(layer, [Terrain.hazard(rect, 2, CG.DamageType.FIRE)])

func test_a_slow_hazard_matches_the_rectangle_it_replaces() -> void:
	var rect := Rect2(-20.0, -60.0, 60.0, 120.0)
	var layer := _layer_with(_paint(_HAZARD_SLOW, rect))
	var f := Terrain.make(Terrain.Kind.HAZARD, rect)
	f.applies_status_enabled = true
	f.applies_status = CG.Status.SLOWED
	f.status_duration_ticks = 45
	_assert_grids_match(layer, [f])

## The cover room's own shape: five disjoint pillars, loaded in one pass.
## Order in the dictionary is not fight order (#680's ordering trap), so this
## also proves the loader does not depend on `TileMapLayer`'s own iteration.
func test_five_disjoint_pillars_match_five_rects() -> void:
	var rects := [
		Rect2(-300.0, -250.0, 100.0, 100.0),
		Rect2(-300.0, -50.0, 100.0, 100.0),
		Rect2(-300.0, 150.0, 100.0, 100.0),
		Rect2(-120.0, -150.0, 100.0, 100.0),
		Rect2(-120.0, 50.0, 100.0, 100.0),
	]
	var cells := {}
	var features: Array = []
	for r in rects:
		cells.merge(_paint(_PILLAR, r))
		features.append(Terrain.make(Terrain.Kind.PILLAR, r))
	var layer := _layer_with(cells)
	_assert_grids_match(layer, features)

## Sight blocking must survive the round trip, not just the stored fields --
## a pillar that reports the right `kind` but never grows a collider is still
## a broken port.
func test_loaded_wall_blocks_sight_the_same_as_the_rectangle() -> void:
	var rect := Rect2(-10.0, -50.0, 20.0, 100.0)
	var layer := _layer_with(_paint(_WALL, rect))
	var loaded := TerrainGridLoader.grid_from_layer(layer)
	var built := TerrainGrid.from_features([Terrain.make(Terrain.Kind.WALL, rect)])
	assert_eq(loaded.sight_blocked(Vector2(-100, 0), Vector2(100, 0)),
		built.sight_blocked(Vector2(-100, 0), Vector2(100, 0)))
