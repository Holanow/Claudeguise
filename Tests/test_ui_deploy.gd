extends "res://Tests/TestCase.gd"

const CanvasScript := preload("res://Scripts/UI/LevelEditorCanvas.gd")

## Issue 145: place your party before the fight starts.
##
## The player asked three times. The acceptance criterion that matters is the
## last one in the issue -- "positions used by the fight" -- so that is asserted
## end to end here through the real `CombatSim.build`, and again on a real
## launch with a screenshot. Everything else on this screen could be perfect and
## the feature would still be worthless if the fight ignored the placement.
##
## **The drag itself is not driven through synthesized input and cannot be.**
## Measured on this project: a pushed `InputEventMouseMotion` does not carry the
## position it is pushed with -- the viewport reads a motion's position from the
## real cursor, which no scripted run moves, so every pushed position arrives as
## the same coordinate. A test that "drags" that way asserts a stationary
## cursor. The grab, the move, the clamp and the terrain refusal are each
## callable and each tested; the drag is verified by launching the game.

func _party(n: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	var ids := Registry.all_class_ids()
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

func _screen(cfg: RunConfig, encounter = null) -> DeployView:
	var screen := DeployView.create()
	screen._ready()
	screen.open(cfg, encounter)
	return screen

# ---------------------------------------------------------------------------
# The criterion that matters: the fight uses the positions.
# ---------------------------------------------------------------------------

## End to end through the real `CombatSim.build`. Not "the screen stored the
## number" -- the units the simulation creates must stand where the player put
## them, because every other assertion in this file is worthless if this fails.
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
func test_without_the_deploy_screen_the_party_stands_somewhere_else() -> void:
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
	assert_eq(placed.terrain, base.terrain, "same terrain")

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
	# Inside the zone AND inside the arena: x in [-458, -182] once the 22-unit
	# radius is taken off both ends. My first fixture used -500, which is
	# outside the arena's own left wall -- the clamp was right and the test was
	# wrong, which is worth a line rather than a silent edit.
	var inside := Vector2(-300.0, 60.0)
	assert_eq(CanvasScript.clamp_to_deploy_zone(inside, radius), inside,
		"a legal position must not be moved")

func test_a_pawn_cannot_be_placed_outside_the_arena() -> void:
	var radius := 22.0
	var below := CanvasScript.clamp_to_deploy_zone(Vector2(-500.0, 99999.0), radius)
	assert_almost_eq(below.y, CG.ARENA_HALF_HEIGHT - radius, 0.001)
	var left := CanvasScript.clamp_to_deploy_zone(Vector2(-99999.0, 0.0), radius)
	assert_almost_eq(left.x, -CG.ARENA_HALF_WIDTH + radius, 0.001)

## heron's rooms have walls and pits, and dropping a pawn inside one would start
## the fight with a unit stuck in terrain. Refused using the same
## `Terrain.point_is_blocked` the simulation's own movement uses, so the screen
## and the fight cannot disagree about what counts as blocked.
func test_a_pawn_cannot_be_dropped_inside_a_wall() -> void:
	var canvas := Control.new()
	canvas.set_script(CanvasScript)
	canvas._ready()
	canvas.mode = CanvasScript.Mode.MOVE_PARTY
	canvas.party_radius = 22.0
	var wall_rect := Rect2(Vector2(-420.0, -60.0), Vector2(120.0, 120.0))
	canvas.terrain = [Terrain.make(Terrain.Kind.WALL, wall_rect)]
	var start := Vector2(-250.0, 200.0)
	var spawns: Array[Vector2] = [start]
	canvas.party_spawns = spawns

	assert_eq(canvas.grab_party_spawn(start), 0, "the pawn must be grabbable where it stands")
	var into_wall := wall_rect.get_center()
	assert_false(canvas.move_held_party_spawn(into_wall), "a move into a wall must be refused")
	assert_eq(canvas.party_spawns[0], start, "a refused move keeps the last good position")

	# And the same canvas must still accept a legal move, or "refuses
	# everything" would pass the assertion above.
	var clear := Vector2(-250.0, -180.0)
	assert_true(canvas.move_held_party_spawn(clear), "a clear position must be accepted")
	assert_eq(canvas.party_spawns[0], clear)
	canvas.free()

func test_grabbing_picks_the_nearest_pawn_and_misses_cleanly() -> void:
	var canvas := Control.new()
	canvas.set_script(CanvasScript)
	canvas._ready()
	canvas.party_radius = 22.0
	var spawns: Array[Vector2] = [Vector2(-400.0, 0.0), Vector2(-400.0, 100.0)]
	canvas.party_spawns = spawns
	assert_eq(canvas.grab_party_spawn(Vector2(-395.0, 96.0)), 1, "nearest wins")
	assert_eq(canvas.grab_party_spawn(Vector2(0.0, 0.0)), -1, "empty ground grabs nothing")
	assert_false(canvas.move_held_party_spawn(Vector2(-400.0, 0.0)),
		"with nothing held, a move must do nothing rather than move pawn 0")
	canvas.free()

# ---------------------------------------------------------------------------
# The screen
# ---------------------------------------------------------------------------

## It must open on the status quo -- exactly where the fight would have put the
## party with no deploy screen at all -- and it takes those from
## `CombatSim.party_spawn_position` rather than reimplementing the overflow
## rule, so the two cannot drift.
func test_the_screen_opens_where_the_fight_would_have_started_the_party() -> void:
	var cfg := _cfg()
	var screen := _screen(cfg)
	var encounter = Registry.get_encounter(cfg.encounter_id)
	var got := screen.placements()
	assert_eq(got.size(), cfg.party.size(), "one marker per party member")
	for i in cfg.party.size():
		assert_eq(got[i], CombatSim.party_spawn_position(encounter, i),
			"marker %d must open on the authored spawn" % i)
	screen.free()

## A party larger than the room's authored spawn list is the overflow case, and
## it is the one a reimplementation would have got wrong. Every marker must
## still land inside the deploy zone the screen draws.
func test_every_opening_marker_is_inside_the_zone_the_screen_draws() -> void:
	for encounter_id in Registry.all_encounter_ids():
		var cfg := _cfg()
		cfg.encounter_id = encounter_id
		var screen := _screen(cfg)
		for i in screen.placements().size():
			var p: Vector2 = screen.placements()[i]
			assert_true(p.x <= CG.party_deploy_max_x() + 0.001,
				"%s marker %d opens at x=%.1f, past the deploy line %.1f" % [encounter_id, i, p.x, CG.party_deploy_max_x()])
		screen.free()

## Four identical dots would place a party without answering the question the
## screen exists for. Only one class can redirect an enemy and the Warden kills
## nearest-first, so which pawn is which is the decision.
func test_each_marker_is_named_so_the_player_knows_who_stands_where() -> void:
	var cfg := _cfg()
	var screen := _screen(cfg)
	var labels: Array = screen._canvas.party_labels
	assert_eq(labels.size(), cfg.party.size(), "one name per pawn")
	for i in cfg.party.size():
		assert_eq(labels[i], cfg.party[i].display_name)
	screen.free()

## The room's terrain has to reach the canvas or the player is placing blind,
## which the issue calls out as the thing that makes this a decision rather than
## a fiddle. Asserted against a room that actually has terrain, or it proves
## nothing.
func test_the_rooms_terrain_reaches_the_screen() -> void:
	var with_terrain: StringName = &""
	for encounter_id in Registry.all_encounter_ids():
		var e = Registry.get_encounter(encounter_id)
		if not e.terrain.is_empty():
			with_terrain = encounter_id
			break
	assert_true(with_terrain != &"", "no registered room has terrain, so this check would be vacuous")
	var cfg := _cfg()
	cfg.encounter_id = with_terrain
	var screen := _screen(cfg)
	assert_eq(screen._canvas.terrain.size(), Registry.get_encounter(with_terrain).terrain.size(),
		"every feature in the room must reach the canvas")
	assert_true(screen._canvas._floor.terrain.size() > 0,
		"and reach the ArenaFloor that draws it, not only the canvas")
	screen.free()

## Not one of the issue's four bullets, and it should have been. Choosing who
## stands nearest is choosing who meets the front rank first, so a screen that
## hides the enemy line asks the player to pick a formation against nothing --
## the same argument the issue makes for terrain, only stronger.
func test_the_enemy_line_is_on_the_screen_to_place_against() -> void:
	var cfg := _cfg()
	var screen := _screen(cfg)
	var room = Registry.get_encounter(cfg.encounter_id)
	assert_true(room.enemy_spawns.size() > 0, "the fixture room must have enemies")
	assert_eq(screen._canvas.enemy_spawns.size(), room.enemy_spawns.size(),
		"every enemy in the room must reach the screen")
	for i in room.enemy_spawns.size():
		assert_eq(screen._canvas.enemy_spawns[i].position, room.enemy_spawns[i].position,
			"enemy %d must be shown where it will actually stand" % i)
		assert_true(screen._canvas.enemy_spawns[i].radius > 0.0,
			"a zero radius draws nothing, which is the same as not showing it")
	screen.free()

func test_reset_puts_every_pawn_back() -> void:
	var cfg := _cfg()
	var screen := _screen(cfg)
	# Terrain cleared so the move under test cannot be refused by whatever the
	# room happens to contain. Reset is what is being measured here.
	screen._canvas.terrain = []
	var opened := screen.placements()
	screen._canvas.grab_party_spawn(opened[0])
	assert_true(screen._canvas.move_held_party_spawn(Vector2(-300.0, 190.0)))
	assert_ne(screen.placements()[0], opened[0], "the pawn must really have moved first")
	screen.reset_placement()
	assert_eq(screen.placements(), opened, "reset returns to the authored placement")
	screen.free()

## Confirming must hand out what is on the screen. The signal is what `Main`
## turns into the fight, so a screen that emits stale positions would be
## invisible until somebody watched a fight start in the wrong place.
func test_confirming_emits_the_placement_currently_on_the_screen() -> void:
	var cfg := _cfg()
	var screen := _screen(cfg)
	screen._canvas.terrain = []
	var opened := screen.placements()
	screen._canvas.grab_party_spawn(opened[0])
	assert_true(screen._canvas.move_held_party_spawn(Vector2(-300.0, -140.0)))
	assert_ne(screen.placements()[0], opened[0], "the pawn must really have moved first")

	# `seen.assign(...)` and not `seen = ...`: a GDScript lambda captures by
	# value, so rebinding the local inside it leaves the outer array empty and
	# the assertions below read as the signal never firing. It cost a red gate.
	var seen: Array = []
	screen.deploy_confirmed.connect(func(positions): seen.assign(positions))
	screen._on_fight_pressed()
	assert_eq(seen.size(), cfg.party.size())
	assert_eq(seen[0], screen.placements()[0], "the emitted placement must be the one on screen")
	screen.free()

## The level editor shares this canvas and must be unchanged by issue 145: its
## own mode still places enemies, and it passes no labels, so its party pins
## draw as they always did.
func test_the_level_editors_use_of_the_canvas_is_unchanged() -> void:
	var canvas := Control.new()
	canvas.set_script(CanvasScript)
	canvas._ready()
	assert_eq(canvas.mode, CanvasScript.Mode.PLACE_ENEMY, "the editor's default mode is untouched")
	assert_eq(canvas.party_labels.size(), 0, "no labels unless a screen asks for them")
	assert_almost_eq(canvas.party_radius, 6.0, 0.001, "the editor's pin size is unchanged")
	canvas.free()
