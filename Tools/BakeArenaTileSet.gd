extends SceneTree

## Issue 680: the TileSet every room scene draws its terrain from, baked once.
##
##   godot --headless --path . --script res://Tools/BakeArenaTileSet.gd
##
## One tile per `Terrain.Kind` plus `EXTRA_TILES`, at `TerrainGrid.CELL` so a
## tile is exactly a grid cell. Custom data only, no physics layers -- `TerrainGrid`
## answers blocking from `kind` directly and never queries a collision layer.

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

## Issue 680: a tile IS its numbers, and the floor does NOT have exactly one
## hazard -- the chokepoint's is a slow status (above), the Burn Pit's is fire
## damage, and one shared `TileData` cannot hold both. Appended after the
## per-`Kind` tiles so indices 0-4 and everything already baked onto them are
## untouched; index 5 is HAZARD-shaped for movement/sight but carries its own
## damage instead of the status.
const EXTRA_TILES := [
	{
		"kind": Terrain.Kind.HAZARD,
		"colour": Color(0.85, 0.35, 0.05),
		"numbers": {"damage_per_tick": 2, "damage_type": CG.DamageType.FIRE},
	},
]

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
	var total := kinds.size() + EXTRA_TILES.size()
	var img := Image.create(CELL * total, CELL, false, Image.FORMAT_RGBA8)
	var colours: Array[Color] = []
	for k in kinds:
		colours.append(COLOURS[k])
	for extra in EXTRA_TILES:
		colours.append(extra["colour"])
	for i in total:
		var c: Color = colours[i]
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
		## `TileData`, so a second hazard needs a second tile, not a
		## per-placement field -- see `EXTRA_TILES`.
		for field in NUMBERS.get(kinds[i], {}):
			data.set_custom_data(field, NUMBERS[kinds[i]][field])

	for j in EXTRA_TILES.size():
		var extra: Dictionary = EXTRA_TILES[j]
		var coords := Vector2i(kinds.size() + j, 0)
		src.create_tile(coords)
		var data := src.get_tile_data(coords, 0)
		data.set_custom_data("kind", extra["kind"])
		for field in extra["numbers"]:
			data.set_custom_data(field, extra["numbers"][field])

	var total := kinds.size() + EXTRA_TILES.size()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(ts, OUT)
	print("wrote %s (err %d, %d tiles)" % [OUT, err, total])
