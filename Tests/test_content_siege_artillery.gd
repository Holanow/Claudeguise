extends "res://Tests/TestCase.gd"

## Issue 93: the Siege Engine as artillery -- unlimited reach, slow, immobile,
## and unable to choose its own targets.

const SEEDS := 6
const MARK_DURATION_TICKS := 150

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		if cid == &"geysermancer":
			continue
		out.append(PawnFactory.make_preset_pawn(cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out

# ---------------------------------------------------------------------------
# what the content declares
# ---------------------------------------------------------------------------

## The guard the constant's own comment promises instead of a stale note.
func test_arena_span_still_exceeds_the_real_arena_diagonal() -> void:
	var diagonal := Vector2(CG.ARENA_HALF_WIDTH * 2.0, CG.ARENA_HALF_HEIGHT * 2.0).length()
	assert_true(CG.ARENA_SPAN > diagonal,
		"ARENA_SPAN %f no longer covers the arena diagonal %f" % [CG.ARENA_SPAN, diagonal])

func test_engine_bolt_reaches_anywhere_and_only_at_a_marked_target() -> void:
	var bolt := ActionLibrary.get_action(&"siege_engine_bolt")
	assert_not_null(bolt, "siege_engine_bolt is missing from the registry")
	assert_almost_eq(bolt.range_units, CG.ARENA_SPAN, 0.0001,
		"the engine's reach should be the arena span")
	assert_true(bolt.requires_marked_target,
		"the engine must not be able to choose its own targets")

## Issue 763 doubled the engine's fire rate (cycle 30 -> 15), authorised and
## deliberate, which is below the ranged mean this test used to require it
## stay above. Guards the two authorised numbers directly instead.
func test_engine_bolt_cycle_matches_issue_763() -> void:
	var bolt := ActionLibrary.get_action(&"siege_engine_bolt")
	assert_eq(bolt.wind_up_ticks, 11, "engine bolt wind-up drifted from issue 763's authorised value")
	assert_eq(bolt.recover_ticks, 4, "engine bolt recover drifted from issue 763's authorised value")

## Stationary was already true before issue 93 and the issue's only requirement
## was not to break it. That is exactly the kind of fact that gets broken by
## someone tuning an unrelated number, so it is asserted rather than trusted.
func test_the_engine_cannot_move() -> void:
	var engine := EnemyLibrary.get_enemy(&"siege_engine")
	assert_not_null(engine, "siege_engine is missing from the registry")
	assert_almost_eq(engine.move_speed, 0.0, 0.0001, "the siege engine must be stationary")

func test_build_action_is_capped_at_two() -> void:
	var build := ActionLibrary.get_action(&"build_siege_engine")
	assert_eq(build.max_active_summons, 2, "the player asked for a cap of 2")

## The negative half, and the reason it is here: both new fields are opt-in and
## every other action in the game must be untouched by them. Without this, a
## default flipped the wrong way would sail through every assertion above.
func test_no_other_action_is_capped_or_marked_only() -> void:
	for id in ActionLibrary.all_ids():
		var a := ActionLibrary.get_action(id)
		if id != &"siege_engine_bolt":
			assert_false(a.requires_marked_target, "%s should not require a marked target" % id)
		if id != &"build_siege_engine":
			assert_eq(a.max_active_summons, 0, "%s should not carry a summon cap" % id)

# ---------------------------------------------------------------------------
# what a real fight does with it
# ---------------------------------------------------------------------------

## Runs a real fight and reports (engines ever built, peak alive at once, shots
## committed, shots committed at an unmarked target, shots committed at a target
## inside the kite band).
func _run(seed_value: int, encounter_id: StringName) -> Dictionary:
	var state := CombatSim.build(_party(), RoomLibrary.get_room(encounter_id), seed_value)
	var known := state.units.size()
	var engine_ids := {}
	var peak := 0
	var shots := 0
	var shots_at_unmarked := 0
	var shots_inside_kite_band := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		var marked_now := {}
		for u in state.living(CG.Team.ENEMY):
			if u.has_status(CG.Status.MARKED):
				marked_now[u.id] = true
		var seen := state.events.size()

		CombatSim.step(state)

		for i in range(seen, state.events.size()):
			var e := state.events[i]
			if e.kind != CG.EventKind.ACTION_START or e.action_id != &"siege_engine_bolt":
				continue
			shots += 1
			if not marked_now.has(e.target_id):
				shots_at_unmarked += 1
			var engine: CombatUnit = state.unit(e.source_id)
			var target: CombatUnit = state.unit(e.target_id)
			if engine != null and target != null 					and engine.position.distance_to(target.position) < CG.ARENA_SPAN * 0.6:
				shots_inside_kite_band += 1

		while known < state.units.size():
			if state.units[known].enemy_id == &"siege_engine":
				engine_ids[state.units[known].id] = true
			known += 1
		var live := 0
		for id in engine_ids:
			var u: CombatUnit = state.unit(id)
			if u != null and u.alive:
				live += 1
		peak = maxi(peak, live)
	return {
		"built": engine_ids.size(),
		"peak": peak,
		"shots": shots,
		"unmarked": shots_at_unmarked,
		"kite_band": shots_inside_kite_band,
	}

## The cap, asserted where it has to hold: in a real fight, not in the field.
## Before issue 93 this peaked at 7.
func test_never_more_than_two_engines_exist_at_once() -> void:
	var any_built := false
	for s in SEEDS:
		var r := _run(s, &"floor1_room1")
		assert_true(int(r["peak"]) <= 2, "seed %d had %d engines alive at once" % [s, r["peak"]])
		if int(r["built"]) > 0:
			any_built = true
	assert_true(any_built, "no engine was built in any seed, so the cap proves nothing")

## The load-bearing one. An engine must never take a shot at an enemy that is
## not marked, in any fight, on any seed.
func test_an_engine_never_fires_at_an_unmarked_enemy() -> void:
	for s in SEEDS:
		var r := _run(s, &"floor1_room1")
		assert_eq(int(r["unmarked"]), 0,
			"seed %d: engine committed %d shots at an unmarked target" % [s, r["unmarked"]])

## Issue 728: both deleted here. Their premise -- "a marked target survives
## long enough in floor1_room1 for the engine to shoot one" -- died under
## #719: `spotter_mark` lands a third as often once the room's goblins lose
## pile-on targeting, measured in the PR rather than asserted here. What they
## proved, that `siege_engine_bolt` does what it declares, `Tools/DummyRoom.gd`
## already proves at 40/40, more cheaply and without a seed.