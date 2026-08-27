extends RefCounted
class_name RoomLoader

## The bridge from a room scene to what the simulation asks for. Off-tree
## only -- `CombatSim` is `RefCounted` and must never touch a node. Issue 680.

const CELL := 15.0

static func load_room(scene: PackedScene) -> RoomData:
	var root: Room = scene.instantiate()
	var data := RoomData.new()
	data.id = root.id
	data.display_name = root.display_name
	data.pickable = root.pickable

	var terrain: TileMapLayer = root.get_node("Terrain")
	for coords in terrain.get_used_cells():
		var tile_data := terrain.get_cell_tile_data(coords)
		if tile_data == null:
			continue
		data.cells[coords] = _cell_from_tile(tile_data)

	var party_spawns: Node2D = root.get_node("PartySpawns")
	for child in party_spawns.get_children():
		data.party_spawns.append(child.position)

	var enemy_spawns: Node2D = root.get_node("EnemySpawns")
	for child in enemy_spawns.get_children():
		var spawn: EnemySpawn = child
		data.enemy_spawns.append({"enemy_id": spawn.enemy_id, "position": spawn.position})

	root.free()
	return data

static func _cell_from_tile(tile_data: TileData) -> TerrainGrid.Cell:
	var c := TerrainGrid.Cell.new()
	c.kind = int(tile_data.get_custom_data("kind")) as Terrain.Kind
	c.damage_per_tick = int(tile_data.get_custom_data("damage_per_tick"))
	c.damage_type = int(tile_data.get_custom_data("damage_type")) as CG.DamageType
	c.applies_status = int(tile_data.get_custom_data("applies_status")) as CG.Status
	c.applies_status_enabled = bool(tile_data.get_custom_data("applies_status_enabled"))
	c.status_duration_ticks = int(tile_data.get_custom_data("status_duration_ticks"))
	c.status_magnitude = float(tile_data.get_custom_data("status_magnitude"))
	return c
