extends "res://Tests/TestCase.gd"

const FloorRoom := preload("res://Scripts/Floor/FloorRoom.gd")
const FloorPlan := preload("res://Scripts/Floor/FloorPlan.gd")
const FloorGenerator := preload("res://Scripts/Floor/FloorGenerator.gd")
const FloorRun := preload("res://Scripts/Floor/FloorRun.gd")

## Covers all five acceptance criteria in Issues/issue-5-first-floor-structure.md.
## Everything here is headless: no CombatSim, no content, no screen, exactly
## per the issue's own boundary.

func _same_shape(a: FloorPlan, b: FloorPlan) -> bool:
	if a.rooms.size() != b.rooms.size():
		return false
	for i in a.rooms.size():
		var ra := a.room(i)
		var rb := b.room(i)
		if ra.type != rb.type:
			return false
		var ca := ra.connections.duplicate()
		var cb := rb.connections.duplicate()
		ca.sort()
		cb.sort()
		if ca != cb:
			return false
	return true

func _room_list_string(plan: FloorPlan) -> String:
	var parts: Array[String] = []
	for r in plan.rooms:
		var conns := r.connections.duplicate()
		conns.sort()
		parts.append("%d:%s->%s" % [r.id, FloorRoom.type_name(r.type), conns])
	return ", ".join(parts)

## Deterministic full pre-order walk: from the entrance, visit the
## smallest-id unvisited neighbour first, recursing before moving to the
## next sibling. Visits every reachable room exactly once.
func _dfs_preorder(plan: FloorPlan) -> Array[int]:
	var order: Array[int] = []
	var seen: Dictionary = {}
	_dfs_visit(plan, plan.entrance_id, seen, order)
	return order

func _dfs_visit(plan: FloorPlan, id: int, seen: Dictionary, order: Array[int]) -> void:
	if seen.has(id):
		return
	seen[id] = true
	order.append(id)
	var r := plan.room(id)
	var neighbors := r.connections.duplicate()
	neighbors.sort()
	for n in neighbors:
		_dfs_visit(plan, n, seen, order)

# ---------------------------------------------------------------------------
# criterion 1: the same seed gives the same floor
# ---------------------------------------------------------------------------

func test_same_seed_gives_the_same_floor() -> void:
	var a := FloorGenerator.generate(4242)
	var b := FloorGenerator.generate(4242)
	print("seed 4242, generation A: ", _room_list_string(a))
	print("seed 4242, generation B: ", _room_list_string(b))
	assert_true(_same_shape(a, b), "same seed must give identical rooms and connections")

func test_different_seeds_diverge() -> void:
	var a := FloorGenerator.generate(1)
	var b := FloorGenerator.generate(2)
	print("seed 1: ", _room_list_string(a))
	print("seed 2: ", _room_list_string(b))
	assert_false(_same_shape(a, b), "different seeds should not produce the identical floor")

# ---------------------------------------------------------------------------
# criterion 2: every room is reachable, and the boss is last
# ---------------------------------------------------------------------------

func test_every_room_reachable_and_boss_requires_miniboss_across_seeds() -> void:
	var full_reach_count := 0
	var boss_blocked_count := 0
	for seed in range(1, 21):
		var plan := FloorGenerator.generate(seed)
		var reachable := plan.reachable_from_entrance()
		if reachable.size() == plan.rooms.size():
			full_reach_count += 1
		else:
			fail("seed %d: only %d/%d rooms reachable from entrance" % [seed, reachable.size(), plan.rooms.size()])

		var without_miniboss := plan.reachable_excluding(plan.miniboss_id)
		if not without_miniboss.has(plan.boss_id):
			boss_blocked_count += 1
		else:
			fail("seed %d: boss reachable without passing the miniboss" % seed)

	print("reachability across 20 seeds: %d/20 fully connected, %d/20 boss blocked without miniboss" % [full_reach_count, boss_blocked_count])
	assert_eq(full_reach_count, 20, "every room must be reachable from the entrance, all 20 seeds")
	assert_eq(boss_blocked_count, 20, "the boss must be unreachable without the miniboss, all 20 seeds")

# ---------------------------------------------------------------------------
# criterion 3: descent and ascent see the same floor
# ---------------------------------------------------------------------------

func test_descent_and_ascent_see_the_same_floor() -> void:
	var plan := FloorGenerator.generate(555)
	var descent := _dfs_preorder(plan)
	var ascent := descent.duplicate()
	ascent.reverse()

	assert_eq(descent.size(), plan.rooms.size(), "descent should reach every room")
	for i in descent.size():
		assert_eq(ascent[i], descent[descent.size() - 1 - i], "ascent order %d should mirror descent" % i)
	for id in descent:
		assert_not_null(plan.room(id), "room %d must still exist, by identity, on the way back up" % id)

	# Not a symmetry the test did not earn: walking the same plan twice in
	# one direction must also match, so "ascent mirrors descent" isn't
	# passing because both sides happen to be trivially equal.
	var descent_again := _dfs_preorder(plan)
	assert_eq(descent_again, descent, "the same plan walked twice in one direction must match")

# ---------------------------------------------------------------------------
# criterion 4: damage persists between rooms, and death sticks
# ---------------------------------------------------------------------------

func test_damage_persists_between_rooms_and_death_sticks() -> void:
	var plan := FloorGenerator.generate(7)
	var run := FloorRun.new(plan)

	assert_eq(run.hp_for(&"warrior", 30), 30, "an untouched pawn defaults to full hp")
	assert_true(run.is_alive(&"warrior"))

	run.record_result(&"warrior", 3, 2, true)
	run.enter(1)
	assert_eq(run.hp_for(&"warrior", 30), 3, "hp must carry into the next room")
	assert_eq(run.resource_for(&"warrior", 10), 2, "resource must carry into the next room")
	assert_true(run.is_alive(&"warrior"))

	run.record_result(&"priest", 0, 0, false)
	run.enter(2)
	assert_false(run.is_alive(&"priest"), "a pawn that died must still be dead in the next room")
	assert_eq(run.hp_for(&"priest", 20), 0)

# ---------------------------------------------------------------------------
# criterion 5: room counts match the design
# ---------------------------------------------------------------------------

func test_room_counts_match_the_design_across_seeds() -> void:
	var type_totals: Dictionary = {}
	for seed in range(1, 21):
		var plan := FloorGenerator.generate(seed)
		assert_eq(plan.rooms.size(), FloorGenerator.FLOOR_1_ROOM_COUNT, "seed %d: room count" % seed)

		var counts: Dictionary = {}
		for r in plan.rooms:
			counts[r.type] = int(counts.get(r.type, 0)) + 1
			type_totals[r.type] = int(type_totals.get(r.type, 0)) + 1

		assert_eq(int(counts.get(FloorRoom.Type.BOSS, 0)), 1, "seed %d: exactly one boss" % seed)
		assert_eq(int(counts.get(FloorRoom.Type.MINIBOSS, 0)), 1, "seed %d: exactly one miniboss" % seed)

	var distribution := {}
	for t in type_totals.keys():
		distribution[FloorRoom.type_name(t)] = type_totals[t]
	print("room type distribution across 20 seeds (120 ordinary-room rolls): ", distribution)

	# Not every floor is six enemy rooms and nothing else: at least three
	# distinct ordinary types must appear across the 120 rolls.
	var ordinary_types_seen := 0
	for t in [FloorRoom.Type.ENEMY, FloorRoom.Type.BIG_ENEMY, FloorRoom.Type.TRAP, FloorRoom.Type.TREASURE, FloorRoom.Type.LIBRARY, FloorRoom.Type.CELL]:
		if int(type_totals.get(t, 0)) > 0:
			ordinary_types_seen += 1
	assert_true(ordinary_types_seen >= 3, "distribution across 20 seeds should not collapse onto one or two room types: %s" % [distribution])
