extends "res://Tests/TestCase.gd"


## Issue 804: floor 1 is a grid scatter. Every invariant the issue names, plus
## the traversal the live floor and the headless sweeps both walk. Headless
## throughout: no CombatSim, no content, no screen.

const SEEDS := 200

func _shape(plan: FloorPlan) -> String:
	var parts: Array[String] = []
	for r in plan.rooms:
		parts.append("%s@%s->%s" % [r.content_id, r.cell, plan.neighbours_of(r.id)])
	return ", ".join(parts)

# ---------------------------------------------------------------------------
# deterministic from a seed

func test_same_seed_gives_the_same_cells_and_connections() -> void:
	for seed in range(SEEDS):
		assert_eq(_shape(FloorGenerator.generate(seed)), _shape(FloorGenerator.generate(seed)),
			"seed %d must generate identically twice" % seed)

func test_different_seeds_diverge() -> void:
	var shapes := {}
	for seed in range(SEEDS):
		shapes[_shape(FloorGenerator.generate(seed))] = true
	assert_true(shapes.size() > SEEDS / 2,
		"%d seeds collapsed onto %d distinct floors" % [SEEDS, shapes.size()])

# ---------------------------------------------------------------------------
# the invariants, each across every seed

func test_no_two_rooms_share_a_cell() -> void:
	for seed in range(SEEDS):
		var plan := FloorGenerator.generate(seed)
		var seen := {}
		for r in plan.rooms:
			assert_true(not seen.has(r.cell),
				"seed %d: %s and %s both sit at %s" % [seed, seen.get(r.cell, ""), r.content_id, r.cell])
			seen[r.cell] = r.content_id

func test_every_room_is_reachable_from_the_entrance() -> void:
	for seed in range(SEEDS):
		var plan := FloorGenerator.generate(seed)
		var reached := plan.reachable_from_entrance()
		assert_eq(reached.size(), plan.rooms.size(),
			"seed %d: only %d of %d rooms reachable" % [seed, reached.size(), plan.rooms.size()])

func test_the_boss_sits_behind_the_miniboss() -> void:
	for seed in range(SEEDS):
		var plan := FloorGenerator.generate(seed)
		assert_false(plan.reachable_excluding(plan.miniboss_id).has(plan.boss_id),
			"seed %d: the boss is reachable without passing the miniboss" % seed)

func test_the_boss_is_not_adjacent_to_the_entrance() -> void:
	for seed in range(SEEDS):
		var plan := FloorGenerator.generate(seed)
		assert_false(plan.neighbours_of(plan.entrance_id).has(plan.boss_id),
			"seed %d: the boss door is the first thing the player sees" % seed)

func test_ten_authored_rooms_each_placed_once() -> void:
	var expected := FloorGenerator.ORDINARY_IDS.duplicate()
	expected.append(FloorGenerator.MINIBOSS_ID)
	expected.append(FloorGenerator.BOSS_ID)
	expected.sort()
	for seed in range(SEEDS):
		var plan := FloorGenerator.generate(seed)
		assert_eq(plan.rooms.size(), FloorGenerator.FLOOR_1_ROOM_COUNT, "seed %d: room count" % seed)
		var got: Array[StringName] = []
		for r in plan.rooms:
			got.append(r.content_id)
		got.sort()
		assert_eq(got, expected, "seed %d: room ids" % seed)

## Every id the generator places must resolve to a scene. #804: do not build
## room types that have no scene.
func test_every_placed_room_id_has_a_scene() -> void:
	for r in FloorGenerator.generate(1).rooms:
		assert_not_null(RoomLibrary.get_room(r.content_id), "no scene for %s" % r.content_id)

## The scatter must actually scatter: if the entrance were always a dead end,
## or the floor always a corridor, the grid would be buying nothing.
func test_the_scatter_produces_branching_floors() -> void:
	var branchy := 0
	for seed in range(SEEDS):
		var plan := FloorGenerator.generate(seed)
		for r in plan.rooms:
			if plan.neighbours_of(r.id).size() >= 3:
				branchy += 1
				break
	assert_true(branchy > SEEDS / 2, "only %d of %d floors branch at all" % [branchy, SEEDS])

# ---------------------------------------------------------------------------
# connections are derived, not stored

## The one property an independently authored connection list cannot have:
## move a room's cell and its doors move with it, with nothing to re-sync.
func test_connections_follow_the_cells() -> void:
	var plan := FloorGenerator.generate(5)
	var lonely := Vector2i(1000, 1000)
	plan.rooms[plan.entrance_id].cell = lonely
	plan.index_cells()
	assert_eq(plan.neighbours_of(plan.entrance_id), [] as Array[int],
		"a room moved off the grid must lose every door")

func test_adjacency_is_symmetric_and_orthogonal() -> void:
	for seed in range(SEEDS):
		var plan := FloorGenerator.generate(seed)
		for r in plan.rooms:
			for other_id in plan.neighbours_of(r.id):
				var other := plan.room(other_id)
				var delta: Vector2i = other.cell - r.cell
				assert_eq(abs(delta.x) + abs(delta.y), 1, "seed %d: %s is not orthogonal" % [seed, delta])
				assert_true(plan.neighbours_of(other_id).has(r.id), "seed %d: one-way door" % seed)

# ---------------------------------------------------------------------------
# the direction seam the door UI reads

func test_every_exit_carries_the_direction_of_its_door() -> void:
	var plan := FloorGenerator.generate(9)
	for r in plan.rooms:
		for e in plan.exits_of(r.id):
			var other := plan.room(int(e["room_id"]))
			assert_eq(other.cell - r.cell, e["dir"],
				"the door direction must be the grid offset between the two cells")
			assert_ne(FloorPlan.direction_name(e["dir"]), "?", "every door has a name")

# ---------------------------------------------------------------------------
# traversal: cleared rooms stay cleared, and the walk is legal

func test_the_walk_only_ever_steps_to_an_adjacent_room() -> void:
	for seed in range(20):
		var plan := FloorGenerator.generate(seed)
		var walk := FloorWalk.new(plan)
		walk.mark_cleared(walk.current_id)
		while true:
			var route := walk.route_to_next_fight()
			if route.is_empty():
				break
			for id in route:
				assert_true(walk.can_enter(id), "seed %d: stepped to a non-adjacent room" % seed)
				walk.enter(id)
			walk.mark_cleared(walk.current_id)
		assert_true(walk.is_floor_cleared(), "seed %d: the walk did not clear the floor" % seed)

func test_a_cleared_room_is_never_offered_as_a_fight_again() -> void:
	for seed in range(20):
		var plan := FloorGenerator.generate(seed)
		var order := FloorWalk.default_order(plan)
		assert_eq(order.size(), FloorGenerator.FLOOR_1_ROOM_COUNT, "seed %d: fight count" % seed)
		var seen := {}
		for id in order:
			assert_true(not seen.has(id), "seed %d: fought %s twice" % [seed, id])
			seen[id] = true

func test_the_boss_is_the_last_fight() -> void:
	for seed in range(SEEDS):
		var order := FloorWalk.default_order(FloorGenerator.generate(seed))
		assert_eq(order[order.size() - 1], FloorGenerator.BOSS_ID, "seed %d" % seed)

func test_the_miniboss_is_fought_before_the_boss() -> void:
	for seed in range(SEEDS):
		var order := FloorWalk.default_order(FloorGenerator.generate(seed))
		assert_true(order.find(FloorGenerator.MINIBOSS_ID) < order.find(FloorGenerator.BOSS_ID),
			"seed %d" % seed)

func test_the_default_order_is_deterministic() -> void:
	for seed in range(20):
		assert_eq(FloorWalk.default_order(FloorGenerator.generate(seed)),
			FloorWalk.default_order(FloorGenerator.generate(seed)), "seed %d" % seed)

## The negative half of "cleared stays cleared": a room the party walks back
## through on the way somewhere else must not come back as a fight.
func test_walking_back_through_a_cleared_room_does_not_reopen_it() -> void:
	var plan := FloorGenerator.generate(3)
	var walk := FloorWalk.new(plan)
	walk.mark_cleared(walk.current_id)
	var first := walk.route_to_next_fight()
	for id in first:
		walk.enter(id)
	walk.mark_cleared(walk.current_id)
	var here := walk.current_id
	for id in walk.route_to_next_fight():
		walk.enter(id)
	assert_true(walk.is_cleared(here), "a room stays cleared once left")
	assert_false(walk.is_cleared(walk.current_id), "the room walked to is a fresh fight")
