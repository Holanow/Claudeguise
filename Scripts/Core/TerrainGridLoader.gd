extends RefCounted
class_name TerrainGridLoader


## Issue #680 step 2. `TileMapLayer` authors, `TerrainGrid` simulates -- this is
## the bridge. Reads a `TileMapLayer` painted with `arena_tileset.tres` and
## produces the same `TerrainGrid` `TerrainGrid.from_features()` would.

## Recovers `Terrain.Kind` from the two physics layers, per #680's own design:
## both block -> WALL, sight only -> PILLAR, movement only -> PIT, neither
## with a payload -> HAZARD, neither with no payload -> WATER.
static func _kind_of(blocks_movement: bool, blocks_sight: bool,
		damage_per_tick: int, applies_status_enabled: bool) -> Terrain.Kind:
	if blocks_movement and blocks_sight:
		return Terrain.Kind.WALL
	if blocks_sight:
		return Terrain.Kind.PILLAR
	if blocks_movement:
		return Terrain.Kind.PIT
	if damage_per_tick > 0 or applies_status_enabled:
		return Terrain.Kind.HAZARD
	return Terrain.Kind.WATER

static func cell_from_tile_data(td: TileData) -> TerrainGrid.Cell:
	var blocks_movement: bool = td.get_collision_polygons_count(0) > 0
	var blocks_sight: bool = td.get_collision_polygons_count(1) > 0
	var c := TerrainGrid.Cell.new()
	c.damage_per_tick = td.get_custom_data("damage_per_tick")
	c.damage_type = td.get_custom_data("damage_type") as CG.DamageType
	c.move_scale = td.get_custom_data("move_scale")
	c.applies_status = td.get_custom_data("applies_status") as CG.Status
	c.applies_status_enabled = td.get_custom_data("applies_status_enabled")
	c.status_duration_ticks = td.get_custom_data("status_duration_ticks")
	c.status_magnitude = td.get_custom_data("status_magnitude")
	c.kind = _kind_of(blocks_movement, blocks_sight, c.damage_per_tick, c.applies_status_enabled)
	return c

## Every used cell, walked once at build time and written into `grid`'s
## `layer`. Sorted rather than `get_used_cells()`'s own order: a `TileMapLayer`
## makes no ordering promise and a fight must not depend on one that isn't.
static func load_into(layer: TileMapLayer, grid: TerrainGrid, dest: TerrainGrid.Layer) -> void:
	var coords: Array = layer.get_used_cells()
	coords.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	for coord in coords:
		var td := layer.get_cell_tile_data(coord)
		if td == null:
			continue
		grid.stamp_rect(dest, TerrainGrid.rect_of(coord), cell_from_tile_data(td))

static func grid_from_layer(layer: TileMapLayer) -> TerrainGrid:
	var g := TerrainGrid.new()
	load_into(layer, g, TerrainGrid.Layer.FLOOR)
	return g
