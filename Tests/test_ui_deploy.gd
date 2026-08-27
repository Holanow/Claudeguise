extends "res://Tests/TestCase.gd"

const CanvasScript := preload("res://Scripts/UI/LevelEditorCanvas.gd")
const BattleScene := preload("res://Scenes/Battle.tscn")
const MainScene := preload("res://Scenes/Main.tscn")

## Placement, on the screen the fight happens on. The player: "I need to be able
## to place units on the same screen as I battle, I should basically be moving
## them around in a paused battle screen and then unpausing it."

func _party(n: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	var ids := ClassLibrary.all_ids()
	for i in n:
		var cid: StringName = ids[i % ids.size()]
		out.append(PawnFactory.make_starter_pawn(cid, StringName("p%d" % i), "Pawn %d" % i))
	return out

func _cfg(n: int = 4) -> RunConfig:
	var cfg := RunConfig.new()
	cfg.party = _party(n)
	cfg.encounter_id = CG.DEFAULT_ENCOUNTER
	cfg.seed = 12345
	return cfg

## A battle screen held before its first tick, which is what `Main` now opens.
func _held(cfg: RunConfig, positions: Array[Vector2] = []):
	var view = in_tree(BattleScene.instantiate())
	view._ready()
	view.begin_setup(cfg, Registry.get_encounter(cfg.encounter_id), positions)
	return view
func test_the_fight_starts_the_party_where_the_player_put_them() -> void:
	var cfg := _cfg()
	var base = Registry.get_encounter(cfg.encounter_id)
	var chosen: Array[Vector2] = [
		Vector2(-400.0, -120.0), Vector2(-380.0, 40.0),
		Vector2(-250.0, 150.0), Vector2(-420.0, -200.0),
	]
	var placed = DeployView.encounter_with_placement(base, chosen)
	var state = CombatSim.build(cfg.party, placed, cfg.seed)
	var got: Array[Vector2] = []
	for u in state.units:
		if u.team == CG.Team.PLAYER:
			got.append(u.position)
	assert_eq(got.size(), chosen.size(), "every party member must be built")
	for i in chosen.size():
		assert_eq(got[i], chosen[i], "party member %d must start where it was placed" % i)

## And the negative half, because "the fight used my positions" also passes if
## the fight uses *any* positions and the authored ones happen to match. Built
## from the same room with no placement, the party must NOT be standing there.
func test_without_placement_the_party_stands_somewhere_else() -> void:
	var cfg := _cfg()
	var base = Registry.get_encounter(cfg.encounter_id)
	var chosen: Array[Vector2] = [
		Vector2(-400.0, -120.0), Vector2(-380.0, 40.0),
		Vector2(-250.0, 150.0), Vector2(-420.0, -200.0),
	]
	var authored = CombatSim.build(cfg.party, base, cfg.seed)
	var moved := 0
	var i := 0
	for u in authored.units:
		if u.team == CG.Team.PLAYER:
			if u.position != chosen[i]:
				moved += 1
			i += 1
	assert_true(moved > 0, "the fixture must differ from the authored spawns or the test above proves nothing")

## The shared `Registry` encounter must survive being deployed into. Writing
## placement straight into it would change every later fight in that room --
## including the re-run that exists to be a comparison control -- and would do
## it invisibly.
func test_placing_a_party_does_not_edit_the_registrys_room() -> void:
	var base = Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	var before: Array[Vector2] = []
	for p in base.party_spawns:
		before.append(p)
	var placed = DeployView.encounter_with_placement(base, [Vector2(-333.0, 77.0)])
	assert_ne(placed, base, "must be a copy, not the same object")
	assert_eq(base.party_spawns, before, "the shared room must be untouched")
	assert_eq(placed.party_spawns[0], Vector2(-333.0, 77.0))
	# The rest of the room has to come with it, or the fight is in a different
	# place from the one the player was looking at.
	assert_eq(placed.enemy_spawns, base.enemy_spawns, "same enemies")
	assert_eq(placed.cells, base.cells, "same terrain")

# ---------------------------------------------------------------------------
# The constraint, drawn and enforced
# ---------------------------------------------------------------------------

## The deploy zone is the rule encounter authors already follow. A pawn dragged
## past it is pulled back, and by its own radius as well, so a marker cannot
## straddle the line it is constrained by.
func test_a_pawn_cannot_be_placed_past_the_deploy_line() -> void:
	var radius := 22.0
	var far_right := CanvasScript.clamp_to_deploy_zone(Vector2(9999.0, 0.0), radius)
	assert_true(far_right.x <= CG.party_deploy_max_x(),
		"placed at %.1f, the line is %.1f" % [far_right.x, CG.party_deploy_max_x()])
	assert_almost_eq(far_right.x, CG.party_deploy_max_x() - radius, 0.001,
		"the whole marker must be inside the zone, not just its centre")

	# Both directions: a position already legal must come back untouched, or a
	# clamp that pinned everything to one spot would pass the check above.
	var inside := Vector2(-300.0, 60.0)
	assert_eq(CanvasScript.clamp_to_deploy_zone(inside, radius), inside,
		"a legal position must not be moved")

func test_a_pawn_cannot_be_placed_outside_the_arena() -> void:
	var radius := 22.0
	var below := CanvasScript.clamp_to_deploy_zone(Vector2(-500.0, 99999.0), radius)
	assert_almost_eq(below.y, CG.ARENA_HALF_HEIGHT - radius, 0.001)
	var left := CanvasScript.clamp_to_deploy_zone(Vector2(-99999.0, 0.0), radius)
	assert_almost_eq(left.x, -CG.ARENA_HALF_WIDTH + radius, 0.001)

## The same band the level editor draws, on the arena the fight is drawn on, and
## only while the fight is held.
func test_the_band_is_drawn_while_placing_and_gone_once_the_fight_starts() -> void:
	var view = _held(_cfg())
	assert_true(view._deploy_band != null, "no band on the arena at all")
	assert_true(view._deploy_band.visible, "the band must be visible while placing")
	assert_eq(view._deploy_band.get_parent(), view._arena,
		"the band has to share the arena's transform or it is drawn somewhere else")
	assert_eq(view._arena.get_child(0), view._deploy_band, "the band draws behind the units")
	view.start_fight()
	assert_true(view._deploy_band == null or not view._deploy_band.visible,
		"the band must go when the fight starts")
	view.free()

## Dragged past the line, the pawn is pulled back to it -- measured on the real
## screen and not only on the static clamp.
func test_dragging_past_the_line_pulls_the_pawn_back() -> void:
	var cfg := _cfg()
	var view = _held(cfg)
	var id := _first_pawn_id(view.state)
	view._grabbed_unit_id = id
	view._move_grabbed_to(Vector2(9999.0, 0.0))
	assert_true(view.placements()[0].x <= CG.party_deploy_max_x() + 0.001,
		"dragged to x=%.1f, past the line %.1f" % [view.placements()[0].x, CG.party_deploy_max_x()])
	assert_eq(view.state.unit(id).position, view.placements()[0],
		"the unit on screen must stand where the placement says")
	view.free()

## heron's rooms have walls and pits. Refused with the same
## `TerrainGrid.move_blocked` the simulation's own movement uses, so the screen
## and the fight cannot disagree about what counts as blocked.
func test_a_pawn_cannot_be_dropped_inside_a_wall() -> void:
	var cfg := _cfg(1)
	var wall_rect := Rect2(Vector2(-420.0, -60.0), Vector2(120.0, 120.0))
	var room := RoomData.new()
	room.id = &"wren_wall_fixture"
	room.party_spawns = [Vector2(-250.0, 200.0)]
	room.enemy_spawns = [{"enemy_id": &"goblin", "position": Vector2(200.0, 0.0)}]
	var grid := TerrainGrid.new()
	grid.stamp_features([Terrain.make(Terrain.Kind.WALL, wall_rect)])
	room.cells = grid.cells(TerrainGrid.Layer.FLOOR)

	var view = in_tree(BattleScene.instantiate())
	view._ready()
	view.begin_setup(cfg, room)
	var id := _first_pawn_id(view.state)
	view._grabbed_unit_id = id
	view._move_grabbed_to(wall_rect.get_center())
	assert_eq(view.placements()[0], Vector2(-250.0, 200.0),
		"a refused move keeps the last good position")

	# And the same screen must still accept a legal move, or "refuses
	# everything" would pass the assertion above.
	view._move_grabbed_to(Vector2(-250.0, -180.0))
	assert_eq(view.placements()[0], Vector2(-250.0, -180.0), "a clear position must be accepted")
	view.free()

# ---------------------------------------------------------------------------
# The screen
# ---------------------------------------------------------------------------

func _first_pawn_id(state: CombatState) -> int:
	for u in state.units:
		if u.team == CG.Team.PLAYER and u.enemy_id == &"":
			return u.id
	return -1

## It must open on the status quo -- exactly where the fight would have put the
## party with no placement at all -- taken from `CombatSim.party_spawn_position`
## rather than reimplementing the overflow rule, so the two cannot drift.
func test_the_screen_opens_where_the_fight_would_have_started_the_party() -> void:
	var cfg := _cfg()
	var view = _held(cfg)
	var encounter = Registry.get_encounter(cfg.encounter_id)
	var got: Array[Vector2] = view.placements()
	assert_eq(got.size(), cfg.party.size(), "one placement per party member")
	for i in cfg.party.size():
		assert_eq(got[i], CombatSim.party_spawn_position(encounter, i),
			"pawn %d must open on the authored spawn" % i)
	view.free()

## A party larger than the room's authored spawn list is the overflow case, and
## it is the one a reimplementation would have got wrong.
func test_every_opening_position_is_inside_the_band() -> void:
	for encounter_id in Registry.all_encounter_ids():
		var cfg := _cfg()
		cfg.encounter_id = encounter_id
		var view = _held(cfg)
		for i in view.placements().size():
			var p: Vector2 = view.placements()[i]
			assert_true(p.x <= CG.party_deploy_max_x() + 0.001,
				"%s pawn %d opens at x=%.1f, past the deploy line %.1f" % [encounter_id, i, p.x, CG.party_deploy_max_x()])
		view.free()

## The screen opens held, not running, and the button says so. A screen that
## opened running would place nothing and the player would never see the band.
func test_the_screen_opens_held_and_the_button_offers_the_fight() -> void:
	var view = _held(_cfg())
	assert_true(view.setup, "the fight must open held")
	assert_true(view.paused, "held means paused")
	assert_eq(view._pause_button.text, "Start Fight")
	assert_true(view._setup_hint.visible, "the player has to be told they can drag")
	assert_true(view._reset_button.visible, "placement's only undo")
	## The pause dim is for a fight that is held. This one has not begun, and
	## dimming the arena you are placing on is the opposite of what it is for.
	assert_false(view._pause_dim.visible, "the arena must be legible while placing")
	view.start_fight()
	assert_false(view.setup)
	assert_false(view.paused, "Start Fight must actually run the fight")
	assert_eq(view._pause_button.text, "Pause")
	assert_false(view._setup_hint.visible)
	assert_false(view._reset_button.visible)
	view.free()

## The party does not jump when the fight starts. `start_fight` rebuilds the
## state through `begin_with_encounter`, and a rebuild that landed anywhere else
## would move every pawn at the instant the player pressed go.
func test_starting_the_fight_does_not_move_anybody() -> void:
	var cfg := _cfg()
	var view = _held(cfg)
	view._grabbed_unit_id = _first_pawn_id(view.state)
	view._move_grabbed_to(Vector2(-300.0, -140.0))
	var before: Array[Vector2] = view.placements()
	view.start_fight()
	var after: Array[Vector2] = []
	for u in view.state.units:
		if u.team == CG.Team.PLAYER and u.enemy_id == &"":
			after.append(u.position)
	assert_eq(after, before, "the fight started the party somewhere else than the screen showed")
	view.free()

func test_reset_puts_every_pawn_back() -> void:
	var cfg := _cfg()
	var view = _held(cfg)
	var opened: Array[Vector2] = view.placements()
	view._grabbed_unit_id = _first_pawn_id(view.state)
	view._move_grabbed_to(Vector2(-300.0, 190.0))
	assert_ne(view.placements()[0], opened[0], "the pawn must really have moved first")
	view.reset_placement()
	assert_eq(view.placements(), opened, "reset returns to the authored placement")
	assert_eq(view.state.unit(_first_pawn_id(view.state)).position, opened[0],
		"and the unit on screen must go back with it")
	view.free()

## `Main` turns this into the fight it re-runs, so a screen that stayed quiet
## would lose the placement the moment the player pressed Restart.
func test_moving_a_pawn_reports_the_placement() -> void:
	var cfg := _cfg()
	var view = _held(cfg)
	# `seen.assign(...)` and not `seen = ...`: a GDScript lambda captures by
	# value, so rebinding the local inside it leaves the outer array empty.
	var seen: Array = []
	view.placement_changed.connect(func(positions): seen.assign(positions))
	view._grabbed_unit_id = _first_pawn_id(view.state)
	view._move_grabbed_to(Vector2(-300.0, -140.0))
	assert_eq(seen.size(), cfg.party.size())
	assert_eq(seen[0], view.placements()[0], "the reported placement must be the one on screen")
	view.free()

# ---------------------------------------------------------------------------
# Placing and inspecting are both a press on a pawn. This is what tells them
# apart, and it is the design decision in the whole change.
# ---------------------------------------------------------------------------

func _press(view, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	view._on_arena_button(e, at)

func _release(view, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	view._on_arena_button(e, at)

func _drag_to(view, at: Vector2) -> void:
	if at.distance_to(view._press_world) > view._drag_slop():
		view._drag_moved = true
	view._move_grabbed_to(at)

## Where a pawn is DRAWN, which is where a player aims: `unit_at` hit-tests
## against the nudged draw position, not the simulated one.
func _drawn(view, unit_id: int) -> Vector2:
	return BattleView.drawn_position(view.state, view.state.unit(unit_id))

func test_a_press_that_travels_places_the_pawn_and_opens_nothing() -> void:
	var view = _held(_cfg())
	var id := _first_pawn_id(view.state)
	var from: Vector2 = _drawn(view, id)
	_press(view, from)
	assert_eq(view._grabbed_unit_id, id, "a press on your own pawn must pick it up")
	_drag_to(view, Vector2(-300.0, -140.0))
	_release(view, Vector2(-300.0, -140.0))
	assert_eq(view.placements()[0], Vector2(-300.0, -140.0), "the pawn must have moved")
	assert_true(view._unit_card.unit_id < 0, "a drag must not also open the card")
	view.free()

func test_a_press_that_stays_put_opens_the_card_and_moves_nothing() -> void:
	var view = _held(_cfg())
	var was: Vector2 = view.placements()[0]
	var from: Vector2 = _drawn(view, _first_pawn_id(view.state))
	_press(view, from)
	_release(view, from)
	assert_eq(view.placements()[0], was, "a click must not move the pawn")
	assert_eq(view._unit_card.unit_id, _first_pawn_id(view.state),
		"a click on a pawn must still open its card while placing")
	view.free()

## The slop is the whole disambiguation, so a wobble under it has to read as a
## click. Without this the two tests above pass with a threshold of zero, which
## would make the card unreachable with a mouse.
func test_a_wobble_under_the_threshold_is_still_a_click() -> void:
	var view = _held(_cfg())
	var from: Vector2 = _drawn(view, _first_pawn_id(view.state))
	var nudge := from + Vector2(view._drag_slop() * 0.5, 0.0)
	_press(view, from)
	_drag_to(view, nudge)
	_release(view, nudge)
	assert_false(view._drag_moved, "a wobble under the slop is not a drag")
	assert_eq(view._unit_card.unit_id, _first_pawn_id(view.state),
		"a hand that wobbles must still open the card")
	view.free()

## An enemy is not yours to move. It still answers a click, because "what is
## that thing and what is it about to do" is the question placement is for.
func test_an_enemy_cannot_be_picked_up_but_still_answers_a_click() -> void:
	var view = _held(_cfg())
	var enemy: CombatUnit = null
	for u in view.state.units:
		if u.team == CG.Team.ENEMY:
			enemy = u
			break
	assert_true(enemy != null, "the fixture room must have enemies")
	var at: Vector2 = _drawn(view, enemy.id)
	_press(view, at)
	assert_eq(view._grabbed_unit_id, -1, "an enemy must not be draggable")
	_release(view, at)
	assert_eq(view._unit_card.unit_id, enemy.id, "an enemy must still open its card")
	view.free()

# ---------------------------------------------------------------------------
# Determinism. The comparison control, and the reason any of this is worth
# measuring at all.
# ---------------------------------------------------------------------------