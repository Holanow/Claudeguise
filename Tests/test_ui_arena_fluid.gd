extends "res://Tests/TestCase.gd"

## Issue 760: water and blood are a shader now, not a flat fill. What a test can
## hold is the wiring and the edge mask; whether it looks like a liquid is a
## screenshot's job and always was.

const BattleScene := preload("res://Scenes/Battle.tscn")

func _grid_with(kind: Terrain.Kind, cells: Array) -> TerrainGrid:
	var grid := TerrainGrid.new()
	var cell := TerrainGrid.Cell.new()
	cell.kind = kind
	for c in cells:
		grid.stamp_rect(TerrainGrid.Layer.EFFECTS, TerrainGrid.rect_of(c), cell)
	return grid

## The mistake #698 records: `geyser_blast` drew a ring at radius 130 against a
## 50-unit hitbox. A fluid wider than its cells is the same lie, and the mask is
## what stops it -- every side of every painted cell is accounted for, so the
## shader fades inward from an open side and never outward past one.
func test_a_lone_cell_is_open_on_all_four_sides() -> void:
	var arena := ArenaFloor.new()
	arena.grid = _grid_with(Terrain.Kind.WATER, [Vector2i(3, 3)])
	assert_eq(arena.fluid_edge_flags(Vector2i(3, 3), Terrain.Kind.WATER),
		Color(1.0, 1.0, 1.0, 1.0))
	arena.free()

## The seams inside a pool must not soften, or a block of cells reads as a
## chessboard again -- the defect issue 625 fixed for outlines.
func test_a_cell_with_neighbours_reports_only_its_outward_sides() -> void:
	var arena := ArenaFloor.new()
	arena.grid = _grid_with(Terrain.Kind.WATER,
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	## r,g,b,a is left, right, top, bottom.
	assert_eq(arena.fluid_edge_flags(Vector2i(1, 0), Terrain.Kind.WATER),
		Color(0.0, 0.0, 1.0, 1.0))
	assert_eq(arena.fluid_edge_flags(Vector2i(0, 0), Terrain.Kind.WATER),
		Color(1.0, 0.0, 1.0, 1.0))
	arena.free()

## The fluid that arrives last wins (#759), so the two never share a cell -- but
## they do touch, and a blood cell is not a neighbour that keeps water flush.
func test_the_other_fluid_is_not_a_neighbour() -> void:
	var arena := ArenaFloor.new()
	var grid := _grid_with(Terrain.Kind.WATER, [Vector2i(0, 0)])
	var blood := TerrainGrid.Cell.new()
	blood.kind = Terrain.Kind.BLOOD
	grid.stamp_rect(TerrainGrid.Layer.EFFECTS, TerrainGrid.rect_of(Vector2i(1, 0)), blood)
	arena.grid = grid
	assert_eq(arena.fluid_edge_flags(Vector2i(0, 0), Terrain.Kind.WATER).g, 1.0,
		"water flush against blood would erode nothing and the two would merge")
	arena.free()

## One shader, two palettes, per the issue -- not two shaders that drift apart.
func test_both_fluids_run_the_same_shader_with_different_parameters() -> void:
	var arena := in_tree(BattleScene.instantiate()).get_node("Arena")
	var water: ShaderMaterial = arena._water_layer.material
	var blood: ShaderMaterial = arena._blood_layer.material
	assert_eq(water.shader, blood.shader)
	assert_ne(water.get_shader_parameter(&"tint"), blood.get_shader_parameter(&"tint"))
	assert_ne(water.get_shader_parameter(&"speed"), blood.get_shader_parameter(&"speed"))

## Issue 855: the player ruled blood can be red, so it carries its own palette
## entry rather than the physical-damage token #759 gave it.
func test_blood_is_tinted_from_the_palette_not_the_physical_damage_token() -> void:
	var arena := in_tree(BattleScene.instantiate()).get_node("Arena")
	var blood: ShaderMaterial = arena._blood_layer.material
	assert_eq(blood.get_shader_parameter(&"tint"), Palette.ARENA_BLOOD)
	assert_ne(blood.get_shader_parameter(&"tint"),
		Palette.damage_color(CG.DamageType.PHYSICAL))

## `HP_LOW` is byte-identical to `TEAM_ENEMY` and that aliasing has caused three
## defects; a pool under every pawn is the fourth place it could happen.
func test_blood_cannot_be_mistaken_for_the_enemy_team_colour() -> void:
	assert_ne(Palette.ARENA_BLOOD, Palette.TEAM_ENEMY)
	assert_true(Palette.ARENA_BLOOD.v < Palette.TEAM_ENEMY.v - 0.3,
		"a stain that matches the enemy team colour in value competes with it")

## Both pools sit above the ground and below everything the arena draws on
## itself, and `z_index` is what holds that -- `BattleView._rebuild_units` frees
## every child of the arena, so tree order is not ours to depend on.
func test_the_pools_sit_between_the_ground_and_the_shots() -> void:
	var arena := in_tree(BattleScene.instantiate()).get_node("Arena")
	assert_true(arena._ground_layer.z_index < arena._water_layer.z_index)
	assert_eq(arena._water_layer.z_index, arena._blood_layer.z_index)
	assert_true(arena._blood_layer.z_index < 0, "a pool must not draw over a shot")

## The layers come back on their own after that sweep, or the arena stays blank
## for the rest of the fight.
func test_the_layers_rebuild_after_the_arena_is_swept() -> void:
	var arena := in_tree(BattleScene.instantiate()).get_node("Arena")
	for child in arena.get_children():
		arena.remove_child(child)
		child.free()
	## Freed rather than nulled: `_rebuild_units` leaves a dead reference, not
	## an empty one, and `is_instance_valid` is what has to tell them apart.
	arena._process(0.0)
	assert_true(is_instance_valid(arena._water_layer))
	assert_eq(arena.get_child_count(), 3)
