extends "res://Tests/TestCase.gd"


## Issue 420: `leave_harmful_ground`, the third MOVEMENT op and the first that
## is not defined relative to a target.

## A band 200 wide, the width of the Burn Pit's, centred on the pawn's spot.
const BAND := Rect2(-100.0, -270.0, 200.0, 540.0)

func _fire(rect: Rect2) -> TerrainFeature:
	return Terrain.hazard(rect, 2, CG.DamageType.FIRE)


func _plan(action_id: StringName = &"", gated: bool = false) -> Plan:
	var targeting := PlanFixtures.block(&"target_nearest_enemy")
	var movement := PlanFixtures.block(&"leave_harmful_ground")
	var blocks: Array[PlanBlock] = [targeting, movement]
	if action_id != &"":
		var action := PlanFixtures.block(&"use_action", {"action_id": action_id})
		blocks.append(action)
	var p := Plan.new()
	p.id = &"off_the_fire"
	p.display_name = "Off the fire"
	p.blocks = blocks
	if gated:
		var condition := PlanFixtures.block(&"self_on_harmful_ground")
		p.condition = condition as ConditionBlock
	return p


## One pawn, one living enemy, and whatever terrain the case is about.
func _situation(plan: Plan, pawn_at: Vector2, foe_at: Vector2, features: Array) -> Array:
	var pawn := PawnFactory.make_starter_pawn(&"geysermancer", &"p0", "P")
	pawn.plans = [plan]
	var state := CombatSim.build([pawn], Registry.get_encounter(&"floor1_ghoul_den"), 1, SimDeps.new())
	var me: CombatUnit = null
	var foe: CombatUnit = null
	for u in state.units:
		if u.team == CG.Team.PLAYER and me == null:
			me = u
		elif u.team == CG.Team.ENEMY and foe == null:
			foe = u
	for u in state.units:
		if u.team == CG.Team.ENEMY and u != foe:
			u.alive = false
	me.position = pawn_at
	me.resource = me.resource_max
	foe.position = foe_at
	state.grid.stamp_features(features)
	return [state, me, foe]


func test_a_pawn_standing_in_fire_is_sent_to_ground_that_does_not_harm() -> void:
	var s := _situation(_plan(), Vector2(0.0, 0.0), Vector2(300.0, 0.0), [_fire(BAND)])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_not_null(intent, "a movement block owns the tick; it must not fall through silently")
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_eq(intent.source_plan, &"off_the_fire", "the log must name the plan that moved the pawn")
	assert_false(CombatSim.standing_harms(state, intent.destination),
		"the destination must not itself harm, got %s" % intent.destination)


## **The negative half.** Ground that costs nothing is not somewhere to run from.
func test_a_pawn_on_safe_ground_does_not_walk_anywhere() -> void:
	var s := _situation(_plan(), Vector2(-300.0, 0.0), Vector2(300.0, 0.0), [_fire(BAND)])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_not_null(intent)
	assert_ne(intent.kind, CG.IntentKind.MOVE_TO, "safe ground is not a reason to move")


## A room with no hazard in it at all must never move a pawn either.
func test_a_room_with_no_hazard_never_moves_the_pawn() -> void:
	var s := _situation(_plan(), Vector2(0.0, 0.0), Vector2(300.0, 0.0), [])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_not_null(intent)
	assert_ne(intent.kind, CG.IntentKind.MOVE_TO)


## Everything in reach harms: the row steps aside for the next one rather than
## walking somewhere that is no better, the same as `move_into_cover` in a room
## with no cover.
func test_a_pawn_with_nowhere_clear_falls_through_to_the_next_plan() -> void:
	var everywhere := _fire(Rect2(-CG.ARENA_HALF_WIDTH, -CG.ARENA_HALF_HEIGHT,
		CG.ARENA_HALF_WIDTH * 2.0, CG.ARENA_HALF_HEIGHT * 2.0))
	var s := _situation(_plan(), Vector2(0.0, 0.0), Vector2(300.0, 0.0), [everywhere])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	assert_true(PlanInterpreter.decide(state, me) == null,
		"with no clear ground the block must let the next row try")


## The nearest way out, not just any way out: from 40 units inside the western
## edge of a band the pawn leaves westward.
func test_the_pawn_takes_the_nearest_way_out() -> void:
	var s := _situation(_plan(), Vector2(-60.0, 0.0), Vector2(300.0, 0.0), [_fire(BAND)])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_true(intent.destination.x < -100.0,
		"the western edge is 40 units away and the eastern 160, got %s" % intent.destination)


## A hazard that costs nothing is not harmful ground -- the same rule
## `_hazard_harms` applies to the condition, applied to the consequence.
func test_a_decorative_hazard_is_not_a_reason_to_move() -> void:
	var decoration := Terrain.make(Terrain.Kind.HAZARD, BAND)
	var s := _situation(_plan(), Vector2(0.0, 0.0), Vector2(300.0, 0.0), [decoration])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_not_null(intent)
	assert_ne(intent.kind, CG.IntentKind.MOVE_TO)


## Never inside a wall: a spot the pawn could not stand in is not an escape.
func test_the_destination_is_never_inside_terrain() -> void:
	var features := [
		_fire(Rect2(-100.0, -100.0, 200.0, 200.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-300.0, -300.0, 200.0, 600.0)),
	]
	var s := _situation(_plan(), Vector2(0.0, 0.0), Vector2(300.0, 0.0), features)
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_false(state.grid.move_blocked(intent.destination, me.radius),
		"walked into a wall at %s" % intent.destination)
	assert_false(CombatSim.standing_harms(state, intent.destination))


## The destination is inside the arena, so the sim's own clamp never has to
## quietly rewrite where the plan said to stand.
func test_the_destination_is_inside_the_arena() -> void:
	var s := _situation(_plan(), Vector2(-CG.ARENA_HALF_WIDTH, -CG.ARENA_HALF_HEIGHT),
		Vector2(300.0, 0.0), [_fire(Rect2(-CG.ARENA_HALF_WIDTH, -CG.ARENA_HALF_HEIGHT, 200.0, 200.0))])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_true(absf(intent.destination.x) <= CG.ARENA_HALF_WIDTH
		and absf(intent.destination.y) <= CG.ARENA_HALF_HEIGHT,
		"destination outside the arena: %s" % intent.destination)


## Same state, same answer, every time: no rng in the search.
func test_the_search_is_deterministic() -> void:
	var first := Vector2.INF
	for i in 5:
		var s := _situation(_plan(), Vector2(10.0, -30.0), Vector2(300.0, 0.0), [_fire(BAND)])
		var intent := PlanInterpreter.decide(s[0], s[1])
		if i == 0:
			first = intent.destination
		assert_eq(intent.destination, first)


## Standing clear with an action in the row: the pawn acts from where it is.
func test_a_clear_pawn_fires_the_action_in_its_own_row() -> void:
	var s := _situation(_plan(&"geyser_blast"), Vector2(-300.0, 0.0), Vector2(-260.0, 0.0), [_fire(BAND)])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION, "clear ground plus a live action means act")
	assert_eq(intent.action_id, &"geyser_blast")


## The whole row the issue asks for, end to end: gated on the condition, the
## pawn walks off the fire, and a tick later it is standing on ground that does
## not hurt it.
func test_the_gated_row_actually_gets_the_pawn_out_of_the_fire() -> void:
	var s := _situation(_plan(&"", true), Vector2(0.0, 0.0), Vector2(300.0, 0.0), [_fire(BAND)])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	assert_true(CombatSim.standing_harms(state, me.position), "the fixture must start the pawn in the fire")
	for i in 60:
		if not CombatSim.standing_harms(state, me.position):
			break
		CombatSim.step(state)
	assert_false(CombatSim.standing_harms(state, me.position),
		"still in the fire after 60 ticks, at %s" % me.position)


## The op is one block, so the row costs the same as any other movement row.
func test_the_op_takes_no_argument_and_costs_one_block() -> void:
	assert_true(BlockCatalog.movement(&"leave_harmful_ground").operands().is_empty(),
		"an argument here would be a number the room decides, not the pawn")
	assert_eq(_plan().block_count(), 2, "targeting plus movement, and the movement half is one block")


## **Issue 424, the defect this file pinned, now stated the other way round.**
## `keep_distance` named its destination from the target and never looked at the
## ground there, and `_avoid_hazard` diverts a step that lands in fire rather
## than a goal that sits in it.
func _kite(range_units: float) -> Plan:
	var targeting := PlanFixtures.block(&"target_nearest_enemy")
	var movement := PlanFixtures.block(&"keep_distance", {"range_units": range_units})
	var kite := Plan.new()
	kite.id = &"kite_210"
	kite.display_name = "Hold %d" % int(range_units)
	kite.blocks = [targeting, movement]
	return kite

func test_the_kite_band_will_not_name_a_destination_that_burns() -> void:
	var s := _situation(_kite(210.0), Vector2(-200.0, 0.0), Vector2(300.0, 0.0),
		[_fire(Rect2(-100.0, -270.0, 200.0, 540.0))])
	var intent := PlanInterpreter.decide(s[0], s[1])
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_false(CombatSim.standing_harms(s[0], intent.destination),
		"the row sent the pawn to %s, which burns" % intent.destination)

## The band is kept exactly, so the row still holds the distance it promises.
## Without this the assertion above would pass on any point off the fire,
## including one the player never asked for.
func test_the_destination_is_still_on_the_band_it_was_told_to_hold() -> void:
	var s := _situation(_kite(210.0), Vector2(-200.0, 0.0), Vector2(300.0, 0.0),
		[_fire(Rect2(-100.0, -270.0, 200.0, 540.0))])
	var foe: CombatUnit = s[2]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(s[0], me)
	assert_almost_eq(foe.position.distance_to(intent.destination) - me.radius - foe.radius, 210.0, 0.5,
		"the destination must sit at the requested distance, not merely somewhere safe")

## The instrument check. With no fire authored the row names the point it always
## named, so the assertions above measure the hazard and not the sweep.
func test_with_no_hazard_the_row_names_the_bearing_it_already_faced() -> void:
	var s := _situation(_kite(210.0), Vector2(-200.0, 0.0), Vector2(300.0, 0.0), [])
	var foe: CombatUnit = s[2]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(s[0], me)
	var straight: Vector2 = foe.position 		+ (me.position - foe.position).normalized() * (210.0 + me.radius + foe.radius)
	assert_almost_eq(intent.destination.distance_to(straight), 0.0, 0.5,
		"unburnt and unblocked, the sweep must return the first bearing it tried")

## A pawn inside the band standing in fire has not arrived: the row promises
## ground that does not harm, so it keeps walking rather than firing from there.
func test_standing_in_fire_inside_the_band_is_not_arriving() -> void:
	var s := _situation(_kite(210.0), Vector2(33.0, 0.0), Vector2(300.0, 0.0),
		[_fire(Rect2(-100.0, -270.0, 200.0, 540.0))])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	assert_true(CombatSim.standing_harms(state, me.position), "the fixture puts the pawn in the fire")
	assert_almost_eq(s[2].position.distance_to(me.position) - me.radius - s[2].radius, 210.0, 0.5,
		"and inside the band")
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO,
		"it held station in the fire because the band alone counted as arrived")
	assert_false(CombatSim.standing_harms(state, intent.destination))

## When every bearing on the band burns there is no honest answer, so the row
## steps aside for the next one the way `move_into_cover` does with no cover.
func test_a_band_that_burns_all_the_way_round_falls_through() -> void:
	var s := _situation(_kite(210.0), Vector2(-200.0, 0.0), Vector2(300.0, 0.0),
		[_fire(Rect2(-2000.0, -2000.0, 4000.0, 4000.0))])
	assert_eq(PlanInterpreter.decide(s[0], s[1]), null,
		"a row with nowhere to stand must hand the tick on, not pick a fire")


func test_the_op_has_a_sentence_and_is_offered_to_the_editor() -> void:
	assert_true(BlockCatalog.MOVEMENT_OPS.has(&"leave_harmful_ground"))
	assert_eq(BlockCatalog.movement(&"leave_harmful_ground").describe(), "move off harmful ground")
