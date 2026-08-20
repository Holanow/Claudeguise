extends "res://Tests/TestCase.gd"

const CoreActions := preload("res://Scripts/Content/Modules/core_actions.gd")

## Issue 93: the Siege Engine as artillery -- unlimited reach, slow, immobile,
## and unable to choose its own targets.

const SEEDS := 6
const MARK_DURATION_TICKS := 150

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in Registry.all_class_ids():
		if cid == &"geysermancer":
			continue
		out.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out

# ---------------------------------------------------------------------------
# what the content declares
# ---------------------------------------------------------------------------

## The guard `core_actions.gd`'s own comment promises instead of a stale note.
func test_arena_span_still_exceeds_the_real_arena_diagonal() -> void:
	var diagonal := Vector2(CG.ARENA_HALF_WIDTH * 2.0, CG.ARENA_HALF_HEIGHT * 2.0).length()
	assert_true(CoreActions.ARENA_SPAN > diagonal,
		"ARENA_SPAN %f no longer covers the arena diagonal %f" % [CoreActions.ARENA_SPAN, diagonal])

func test_engine_bolt_reaches_anywhere_and_only_at_a_marked_target() -> void:
	var bolt := Registry.get_action(&"siege_engine_bolt")
	assert_not_null(bolt, "siege_engine_bolt is missing from the registry")
	assert_almost_eq(bolt.range_units, CoreActions.ARENA_SPAN, 0.0001,
		"the engine's reach should be the arena span")
	assert_true(bolt.requires_marked_target,
		"the engine must not be able to choose its own targets")

## "Lower than average attack speed", checked against the average rather than
## against a number typed here -- a hand-written threshold would agree with
## itself forever while the rest of the bestiary moved underneath it.
func test_engine_bolt_is_slower_than_every_other_ranged_action() -> void:
	var bolt := Registry.get_action(&"siege_engine_bolt")
	var engine_cycle := bolt.wind_up_ticks + bolt.recover_ticks
	var slowest_other := 0
	var total := 0
	var n := 0
	for id in Registry.all_action_ids():
		if id == &"siege_engine_bolt":
			continue
		var a := Registry.get_action(id)
		if a == null or a.projectile_speed <= 0.0:
			continue
		var cycle := a.wind_up_ticks + a.recover_ticks
		slowest_other = maxi(slowest_other, cycle)
		total += cycle
		n += 1
	assert_true(n > 0, "no other ranged actions found to compare against")
	assert_true(engine_cycle > total / n,
		"engine cycle %d is not slower than the ranged mean %d" % [engine_cycle, total / n])
	assert_true(engine_cycle > slowest_other,
		"engine cycle %d is not slower than the slowest other ranged action %d" % [engine_cycle, slowest_other])

## Stationary was already true before issue 93 and the issue's only requirement
## was not to break it. That is exactly the kind of fact that gets broken by
## someone tuning an unrelated number, so it is asserted rather than trusted.
func test_the_engine_cannot_move() -> void:
	var engine := Registry.get_enemy(&"siege_engine")
	assert_not_null(engine, "siege_engine is missing from the registry")
	assert_almost_eq(engine.move_speed, 0.0, 0.0001, "the siege engine must be stationary")

func test_build_action_is_capped_at_two() -> void:
	var build := Registry.get_action(&"build_siege_engine")
	assert_eq(build.max_active_summons, 2, "the player asked for a cap of 2")

## The negative half, and the reason it is here: both new fields are opt-in and
## every other action in the game must be untouched by them. Without this, a
## default flipped the wrong way would sail through every assertion above.
func test_no_other_action_is_capped_or_marked_only() -> void:
	for id in Registry.all_action_ids():
		var a := Registry.get_action(id)
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
	var state := CombatSim.build(_party(), Registry.get_encounter(encounter_id), seed_value)
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
			if engine != null and target != null 					and engine.position.distance_to(target.position) < CoreActions.ARENA_SPAN * 0.6:
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

## And the other direction, which is the one that would otherwise pass silently:
func test_engines_actually_fire_in_a_real_fight() -> void:
	var shots := 0
	for s in SEEDS:
		shots += int(_run(s, &"floor1_room1")["shots"])
	assert_true(shots > 0,
		"no engine fired a single shot across %d real fights -- marking is not reaching them" % SEEDS)

## The immobile-unit branch in `DefaultBehavior`, checked through a real fight.
func test_an_engine_fires_at_a_target_inside_its_kite_band() -> void:
	var inside := 0
	for s in SEEDS:
		inside += int(_run(s, &"floor1_room1")["kite_band"])
	assert_true(inside > 0,
		"no engine ever committed a shot inside 0.6 of its own range -- the kite branch is swallowing them")
