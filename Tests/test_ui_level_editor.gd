extends "res://Tests/TestCase.gd"


## Issue 19: the level editor. Placement is asserted through the canvas's own
## public methods (place_enemy/place_terrain), not through synthesized mouse
## events — same split InspectPanel's editing tests use, and for the same
## reason: this is the logic under the input handler, not a proxy for it.
##
## No test in this file writes to disk. `_encounter_dict` (the exact save
## format agreed with dace on the board) is pure and checked directly;
## `_on_save_pressed`'s disk-writing tail is only exercised by a real save
## through the running game, not the gate — a JSON file under
## res://Assets/Rooms/ left behind by every gate run would be a tracked-
## directory side effect no test suite should have.

# ---------------------------------------------------------------------------
# LevelEditorCanvas
# ---------------------------------------------------------------------------

func _make_canvas() -> LevelEditorCanvas:
	var c := LevelEditorCanvas.new()
	c._ready()
	return c

func test_compute_layout_produces_a_positive_scale_for_a_real_size() -> void:
	var layout := LevelEditorCanvas.compute_layout(Vector2(1280.0, 720.0))
	assert_true(layout.scale.x > 0.0)
	assert_true(layout.scale.y > 0.0)

func test_compute_layout_degrades_safely_on_a_zero_size() -> void:
	var layout := LevelEditorCanvas.compute_layout(Vector2.ZERO)
	assert_eq(layout.scale, Vector2.ONE)

func test_world_and_local_conversion_round_trips() -> void:
	var c := _make_canvas()
	c.size = Vector2(1280.0, 720.0)
	c._relayout()
	var world := Vector2(120.0, -60.0)
	var back := c.local_to_world(c.world_to_local(world))
	assert_almost_eq(back.x, world.x, 0.01)
	assert_almost_eq(back.y, world.y, 0.01)
	c.free()

func test_place_enemy_appends_to_enemy_spawns_and_emits() -> void:
	var c := _make_canvas()
	var emitted: Array = []
	c.enemy_placed.connect(func(i): emitted.append(i))
	var index := c.place_enemy(&"goblin", Vector2(100.0, 0.0), 22.0)
	assert_eq(index, 0)
	assert_eq(c.enemy_spawns.size(), 1)
	assert_eq(c.enemy_spawns[0].enemy_id, &"goblin")
	assert_eq(c.enemy_spawns[0].position, Vector2(100.0, 0.0))
	assert_eq(emitted, [0])
	c.free()

func test_remove_enemy_removes_the_right_index() -> void:
	var c := _make_canvas()
	c.place_enemy(&"goblin", Vector2(10.0, 0.0), 22.0)
	c.place_enemy(&"ghoul", Vector2(20.0, 0.0), 16.0)
	c.remove_enemy(0)
	assert_eq(c.enemy_spawns.size(), 1)
	assert_eq(c.enemy_spawns[0].enemy_id, &"ghoul")
	c.free()

func test_place_terrain_appends_and_syncs_the_arena_floor() -> void:
	var c := _make_canvas()
	var emitted: Array = []
	c.terrain_placed.connect(func(i): emitted.append(i))
	var rect := Rect2(-20.0, -20.0, 40.0, 40.0)
	var index := c.place_terrain(Terrain.Kind.WALL, rect)
	assert_eq(index, 0)
	assert_eq(c.terrain.size(), 1)
	assert_eq(c.terrain[0].kind, Terrain.Kind.WALL)
	assert_eq(c.terrain[0].rect, rect)
	assert_eq(emitted, [0])
	# ArenaFloor draws from its own `terrain` field, set by the canvas on
	# every placement -- a room authored here must look like the room a real
	# fight would draw, not a stale copy from before the last placement.
	assert_eq(c._floor.terrain, c.terrain)
	c.free()

func test_hazard_terrain_gets_a_default_damage_so_it_is_not_a_silent_zero() -> void:
	var c := _make_canvas()
	c.place_terrain(Terrain.Kind.HAZARD, Rect2(0.0, 0.0, 40.0, 40.0))
	assert_true(c.terrain[0].damage_per_tick > 0)
	c.free()

func test_remove_terrain_removes_the_right_index() -> void:
	var c := _make_canvas()
	c.place_terrain(Terrain.Kind.WALL, Rect2(0.0, 0.0, 10.0, 10.0))
	c.place_terrain(Terrain.Kind.PIT, Rect2(100.0, 100.0, 10.0, 10.0))
	c.remove_terrain(0)
	assert_eq(c.terrain.size(), 1)
	assert_eq(c.terrain[0].kind, Terrain.Kind.PIT)
	c.free()

## Acceptance criterion 4: reuses Terrain.point_is_blocked directly, the same
## function the real simulation's movement code answers with -- this and a
## real fight can never disagree about what "blocked" means.
func test_has_blocked_enemy_true_only_when_an_enemy_overlaps_blocking_terrain() -> void:
	var c := _make_canvas()
	c.place_terrain(Terrain.Kind.WALL, Rect2(-20.0, -20.0, 40.0, 40.0))
	c.place_enemy(&"goblin", Vector2(500.0, 500.0), 22.0)
	assert_false(c.has_blocked_enemy(), "an enemy far from the wall must not read as blocked")

	c.place_enemy(&"ghoul", Vector2(0.0, 0.0), 22.0)
	assert_true(c.has_blocked_enemy(), "an enemy placed inside the wall's rect must read as blocked")
	c.free()

func test_has_blocked_enemy_ignores_non_blocking_terrain() -> void:
	var c := _make_canvas()
	# PILLAR blocks sight, not movement -- Terrain.point_is_blocked (and the
	# real simulation) must not treat it as blocking an enemy's spawn.
	c.place_terrain(Terrain.Kind.PILLAR, Rect2(-20.0, -20.0, 40.0, 40.0))
	c.place_enemy(&"goblin", Vector2(0.0, 0.0), 22.0)
	assert_false(c.has_blocked_enemy())
	c.free()

# ---------------------------------------------------------------------------
# LevelEditorView
# ---------------------------------------------------------------------------

func _make_view() -> LevelEditorView:
	var v := LevelEditorView.new()
	v._ready()
	return v

func test_screen_builds_its_pickers_and_canvas() -> void:
	var v := _make_view()
	assert_not_null(v._canvas)
	assert_not_null(v._enemy_picker)
	assert_not_null(v._terrain_picker)
	v.free()

## Registry has no all_enemy_ids() (proposed to dace on the board); this
## checks the fallback derivation actually reaches the real bestiary rather
## than an empty or partial list. `floor1_enemies.gd` registers five enemies
## and every one of them is used by at least one registered encounter today,
## so this is a real assertion against real content, not a fixture standing
## in for it.
func test_bestiary_picker_offers_every_enemy_used_by_a_registered_encounter() -> void:
	var v := _make_view()
	var expected := {}
	for encounter_id in Registry.all_encounter_ids():
		for spawn in Registry.get_encounter(encounter_id).enemy_spawns:
			expected[spawn.enemy_id] = true
	assert_true(expected.size() > 0, "expected at least one real registered enemy to test the picker against")
	assert_eq(v._enemy_picker.item_count, expected.size())
	v.free()

func test_terrain_picker_offers_all_four_kinds() -> void:
	var v := _make_view()
	assert_eq(v._terrain_picker.item_count, 4)
	v.free()

## Criterion 3: the deploy zone this screen shows must be the same one a real
## fight respects, not a second guess at CG.party_deploy_max_x().
func test_default_party_spawns_are_inside_the_deploy_zone() -> void:
	var v := _make_view()
	for p in v._default_party_spawns():
		assert_true(p.x <= CG.party_deploy_max_x(), "party spawn at x=%f is outside the deploy zone" % p.x)
	v.free()

func test_save_refuses_an_empty_room_without_touching_disk() -> void:
	var v := _make_view()
	v._on_save_pressed()
	assert_true(v._status_label.text.to_lower().contains("enemy"), v._status_label.text)
	v.free()

func test_save_refuses_a_blocked_enemy_without_touching_disk() -> void:
	var v := _make_view()
	v._canvas.place_terrain(Terrain.Kind.WALL, Rect2(-20.0, -20.0, 40.0, 40.0))
	v._canvas.place_enemy(&"goblin", Vector2(0.0, 0.0), 22.0)
	v._on_save_pressed()
	assert_true(v._status_label.text.to_lower().contains("wall") or v._status_label.text.to_lower().contains("blocked"), v._status_label.text)
	v.free()

## The exact shape posted to TEAM_LOG.md and proposed to dace: flat x/y (and
## x/y/w/h for a rect), kind and damage_type as the enum's own string name.
## This is the one thing that has to hold for a future Registry-side loader
## to read what this screen writes -- checked directly rather than only
## exercised through a real file.
func test_encounter_dict_matches_the_agreed_save_format() -> void:
	var v := _make_view()
	v._canvas.place_enemy(&"goblin", Vector2(150.0, -80.0), 22.0)
	v._canvas.place_terrain(Terrain.Kind.HAZARD, Rect2(-20.0, -20.0, 40.0, 40.0))
	var dict := v._encounter_dict("authored_the_pit", "The Pit")

	assert_eq(dict.id, "authored_the_pit")
	assert_eq(dict.display_name, "The Pit")
	assert_eq(dict.enemy_spawns.size(), 1)
	assert_eq(dict.enemy_spawns[0], {"enemy_id": "goblin", "x": 150.0, "y": -80.0})
	assert_eq(dict.party_spawns.size(), v._canvas.party_spawns.size())
	assert_eq(dict.terrain.size(), 1)
	var t: Dictionary = dict.terrain[0]
	assert_eq(t.kind, "HAZARD")
	assert_eq(t.x, -20.0)
	assert_eq(t.y, -20.0)
	assert_eq(t.w, 40.0)
	assert_eq(t.h, 40.0)
	assert_true(t.damage_per_tick > 0)
	assert_eq(t.damage_type, "FIRE")

	# Round-trips through Godot's own JSON codec, the same one a runtime
	# loader would use -- proves the dict is JSON-safe (StringName/Rect2/enum
	# values are not, on their own), not only that the dict looks right.
	var text := JSON.stringify(dict)
	var parsed = JSON.parse_string(text)
	assert_eq(parsed.id, "authored_the_pit")
	assert_eq(parsed.terrain[0].kind, "HAZARD")
	v.free()

## Criterion 1, the feature rook named as mattering most: a room fights for
## real, through the real BattleView/CombatSim, without the player leaving
## this screen (no Main scene swap happens here at all).
func test_test_room_builds_a_real_encounter_and_starts_a_real_fight() -> void:
	var v := _make_view()
	v._canvas.place_enemy(&"goblin", Vector2(150.0, 0.0), 22.0)
	v._start_test_fight()

	assert_not_null(v._test_battle)
	assert_not_null(v._test_battle.state)
	assert_eq(v._test_battle.state.units.filter(func(u): return u.team == CG.Team.ENEMY).size(), 1)
	assert_false(v._editor_ui.visible, "editor controls should step aside while a test fight is showing")
	v.free()

func test_test_room_refuses_an_empty_room() -> void:
	var v := _make_view()
	v._start_test_fight()
	assert_true(v._test_battle == null, "should not start a test fight with no enemies placed")
	assert_true(v._status_label.text.to_lower().contains("enemy"), v._status_label.text)
	v.free()

func test_ending_the_test_fight_restores_the_editor_and_frees_the_battle() -> void:
	var v := _make_view()
	v._canvas.place_enemy(&"goblin", Vector2(150.0, 0.0), 22.0)
	v._start_test_fight()
	v._end_test_fight()
	assert_true(v._test_battle == null, "ending the test fight should free the embedded BattleView")
	assert_true(v._editor_ui.visible)
	v.free()
