extends SceneTree

## Issue 680: the TileSet every room scene draws its terrain from, baked once.
##
##   godot --headless --path . --script res://Tools/BakeArenaTileSet.gd
##
## One tile per `Terrain.Kind`, at `TerrainGrid.CELL` so a tile is exactly a
## grid cell and the authoring surface cannot disagree with the simulation about
## where a wall is.
##
## Custom data only, and no physics layers. `TerrainGrid` builds its sight
## colliders straight from `kind` and asks no physics query for movement, so a
## collision layer here would be a second, unread answer to "does this block".

const CELL := 15
const ATLAS := "res://Assets/UI/terrain_tiles.png"
const OUT := "res://Scripts/Content/arena_tileset.tres"

## Flat, readable, and only ever seen in the editor -- the game draws terrain
## through ArenaFloor, not through these.
const COLOURS := {
	Terrain.Kind.WALL: Color(0.42, 0.40, 0.46),
	Terrain.Kind.PILLAR: Color(0.60, 0.58, 0.66),
	Terrain.Kind.HAZARD: Color(0.72, 0.28, 0.18),
	Terrain.Kind.PIT: Color(0.10, 0.09, 0.13),
	Terrain.Kind.WATER: Color(0.22, 0.48, 0.72),
}

## Two passes on purpose. A PNG written this run has no import yet, so `load`
## returns null until the editor has seen it: write, `--import`, then bake.
## The floor's authored numbers, per kind. Anything absent keeps the layer
## default, which is zero.
const NUMBERS := {
	Terrain.Kind.HAZARD: {
		"applies_status": CG.Status.SLOWED,
		"applies_status_enabled": 1,
		"status_duration_ticks": 45,
	},
}

func _initialize() -> void:
	if not ResourceLoader.exists(ATLAS):
		_bake_atlas()
		print("run --import, then run this again to bake the TileSet")
		quit(0)
		return
	_bake_tileset()
	quit(0)

func _bake_atlas() -> void:
	var kinds := Terrain.Kind.values()
	var img := Image.create(CELL * kinds.size(), CELL, false, Image.FORMAT_RGBA8)
	for i in kinds.size():
		var c: Color = COLOURS[kinds[i]]
		for y in CELL:
			for x in CELL:
				## A one-pixel darker rim, so a run of the same tile still reads
				## as separate cells when somebody is placing them.
				var edge := x == 0 or y == 0 or x == CELL - 1 or y == CELL - 1
				img.set_pixel(i * CELL + x, y, c.darkened(0.35) if edge else c)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ATLAS.get_base_dir()))
	img.save_png(ATLAS)
	print("wrote %s" % ATLAS)

func _bake_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)

	for name in ["kind", "damage_per_tick", "damage_type", "applies_status",
			"applies_status_enabled", "status_duration_ticks", "status_magnitude"]:
		ts.add_custom_data_layer()
		var at := ts.get_custom_data_layers_count() - 1
		ts.set_custom_data_layer_name(at, name)
		ts.set_custom_data_layer_type(at, TYPE_INT if name != "status_magnitude" else TYPE_FLOAT)

	var src := TileSetAtlasSource.new()
	src.texture = load(ATLAS)
	src.texture_region_size = Vector2i(CELL, CELL)
	## Attached BEFORE the tiles exist: tile data looks its custom data layers up
	## through the TileSet, and a source with no TileSet has none.
	ts.add_source(src, 0)
	var kinds := Terrain.Kind.values()
	for i in kinds.size():
		var coords := Vector2i(i, 0)
		src.create_tile(coords)
		var data := src.get_tile_data(coords, 0)
		data.set_custom_data("kind", kinds[i])
		## A tile IS its numbers: every cell painted with a tile shares one
		## `TileData`, so a second hazard that slows for longer is a second
		## tile, not a per-placement field. Floor 1 has exactly one hazard.
		for field in NUMBERS.get(kinds[i], {}):
			data.set_custom_data(field, NUMBERS[kinds[i]][field])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(ts, OUT)
	print("wrote %s (err %d, %d tiles)" % [OUT, err, kinds.size()])
