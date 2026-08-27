extends SceneTree

## Issue 680: ports `Encounter`s to room scenes by replaying the real
## `TerrainGrid.stamp_features` and painting exactly the cells it produces.
## Never hand-paint a room -- see the issue for why.
##
##   godot --headless --path . --script res://Tools/ConvertRoomsToScenes.gd -- <id> <id> ...
##   With no ids, converts every id in ALL_IDS.

const FloorEncounters := preload("res://Scripts/Content/Modules/floor1_encounters.gd")
const TileSetPath := "res://Scripts/Content/arena_tileset.tres"
const OutDir := "res://Scripts/Content/Rooms"

const ALL_IDS := [
	&"floor1_room1", &"floor1_chokepoint", &"floor1_cover", &"floor1_hazard",
	&"floor1_horde", &"floor1_ghoul_den", &"floor1_sellsword", &"floor1_rat_king",
	&"floor1_warden",
]

## The one place a Cell's payload picks an atlas tile. `2:0` is the sole
## HAZARD tile baked today (the chokepoint's slow); a fire hazard has no tile
## yet and this refuses rather than silently drop the damage. Issue 680.
static func _tile_coords(cell: TerrainGrid.Cell) -> Vector2i:
	if cell.kind == Terrain.Kind.HAZARD and cell.damage_per_tick > 0:
		push_error("ConvertRoomsToScenes: no atlas tile for a damaging hazard yet")
		return Vector2i(-1, -1)
	return Vector2i(cell.kind, 0)

func _initialize() -> void:
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = ALL_IDS
	var by_id: Dictionary = {}
	for e in FloorEncounters.encounters():
		by_id[e.id] = e

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OutDir))
	for raw_id in ids:
		var id := StringName(raw_id)
		if not by_id.has(id):
			push_error("ConvertRoomsToScenes: no encounter '%s'" % id)
			continue
		_convert(by_id[id])
	quit(0)

func _convert(e: Encounter) -> void:
	var grid := TerrainGrid.new()
	grid.stamp_features(e.terrain)
	var floor_cells: Dictionary = grid.cells(TerrainGrid.Layer.FLOOR)

	var root := Node2D.new()
	root.name = "Room"
	root.set_script(load("res://Scripts/Rooms/Room.gd"))
	root.id = e.id
	root.display_name = e.display_name
	root.pickable = e.pickable

	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = load(TileSetPath)
	for coords in floor_cells:
		var tile := _tile_coords(floor_cells[coords])
		if tile == Vector2i(-1, -1):
			return
		terrain.set_cell(coords, 0, tile)
	root.add_child(terrain)
	terrain.owner = root

	var party_spawns := Node2D.new()
	party_spawns.name = "PartySpawns"
	root.add_child(party_spawns)
	party_spawns.owner = root
	for p in e.party_spawns:
		var m := Marker2D.new()
		m.position = p
		party_spawns.add_child(m)
		m.owner = root

	var enemy_spawns := Node2D.new()
	enemy_spawns.name = "EnemySpawns"
	root.add_child(enemy_spawns)
	enemy_spawns.owner = root
	for spawn in e.enemy_spawns:
		var s := Marker2D.new()
		s.set_script(load("res://Scripts/Rooms/EnemySpawn.gd"))
		s.enemy_id = spawn.get("enemy_id", &"")
		s.position = spawn.get("position", Vector2.ZERO)
		enemy_spawns.add_child(s)
		s.owner = root

	var packed := PackedScene.new()
	packed.pack(root)
	var out_path := "%s/%s.tscn" % [OutDir, e.id]
	var err := ResourceSaver.save(packed, out_path)
	print("wrote %s (err %d, %d cells)" % [out_path, err, floor_cells.size()])
	root.free()
