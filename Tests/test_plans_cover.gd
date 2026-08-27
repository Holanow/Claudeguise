extends "res://Tests/TestCase.gd"


## Issue 316: `move_into_cover`, the second MOVEMENT op. Positioning is the
## largest thing a pawn does that the player could not author.

const PILLAR_AT := Rect2(0.0, -40.0, 60.0, 80.0)

func _plan_with(action_id: StringName = &"") -> Plan:
	var targeting := PlanFixtures.block(&"target_nearest_enemy")
	var movement := PlanFixtures.block(&"move_into_cover")
	var blocks: Array[PlanBlock] = [targeting, movement]
	if action_id != &"":
		var action := PlanFixtures.block(&"use_action", {"action_id": action_id})
		blocks.append(action)
	var p := Plan.new()
	p.id = &"cover_test"
	p.display_name = "Take cover"
	p.blocks = blocks
	return p

## One pawn, one living enemy, and whatever terrain the case is about. `alive`
## is a stored bool, so other enemies are switched off directly (#325).
func _situation(plan: Plan, pawn_at: Vector2, foe_at: Vector2, features: Array, class_id: StringName = &"geysermancer") -> Array:
	var pawn := PawnFactory.make_starter_pawn(class_id, &"p0", "P")
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


## In the open with a pillar to one side: the pawn walks to the far side of it.
func test_a_pawn_in_the_open_moves_behind_the_pillar() -> void:
	var s := _situation(_plan_with(), Vector2(-200.0, 200.0), Vector2(-200.0, 0.0),
		[Terrain.make(Terrain.Kind.PILLAR, PILLAR_AT)])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var foe: CombatUnit = s[2]
	var intent := PlanInterpreter.decide(state, me)
	assert_not_null(intent, "a movement block owns the tick; it must not fall through silently")
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_eq(intent.source_plan, &"cover_test", "the log must be able to name the plan that moved the pawn")
	assert_true(state.grid.sight_blocked(foe.position, intent.destination),
		"the destination must actually be out of sight, got %s" % intent.destination)


## **The negative half, and the one that would catch a block that always walks
## somewhere.** An empty room offers no cover, so the row does not apply and the
## next one gets its turn.
func test_an_empty_room_falls_through_to_the_next_plan() -> void:
	var s := _situation(_plan_with(), Vector2(-200.0, 200.0), Vector2(-200.0, 0.0), [])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	assert_true(PlanInterpreter.decide(state, me) == null,
		"with no cover in the room the block must let the next row try")


## Already behind the pillar: the pawn stays put rather than shuffling, which is
## the limit cycle issue 94 found and `KEEP_DISTANCE_BAND` exists to stop.
func test_a_pawn_already_in_cover_holds_still() -> void:
	var s := _situation(_plan_with(), Vector2(30.0, 200.0), Vector2(30.0, -200.0),
		[Terrain.make(Terrain.Kind.PILLAR, PILLAR_AT)])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var foe: CombatUnit = s[2]
	assert_true(state.grid.sight_blocked(foe.position, me.position),
		"fixture check: this pawn should start in cover")
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.IDLE, "already in cover means arrived, not keep walking")
	assert_eq(intent.source_plan, &"cover_test",
		"an idle with no plan on it is the unexplained standing-still issue 98 objects to")


## Cover plus an action is the whole point: "move into cover and raise your
## shield". A movement block refused an action outright until #335 decided what
## a movement block aims at. Issue 593 made Directional Block name a unit rather
## than itself, so what this now pins is that the row keeps the plan's OWN
## target -- the fixture's targeting is `target_nearest_enemy`, and nothing in
## the action overrides it any more.
func test_in_cover_the_pawn_fires_its_action_at_the_target_its_plan_named() -> void:
	var s := _situation(_plan_with(&"warrior_block"), Vector2(30.0, 200.0), Vector2(30.0, -200.0),
		[Terrain.make(Terrain.Kind.PILLAR, PILLAR_AT)], &"warrior")
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	if not me.actions.has(&"warrior_block"):
		me.actions.append(&"warrior_block")
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION, "in cover, the action gets the tick")
	assert_eq(intent.action_id, &"warrior_block")
	var foe: CombatUnit = s[2]
	assert_eq(intent.target_id, foe.id,
		"Directional Block should take the unit its plan named, not silently retarget itself")


## **Design question 4, and the measurement changed the answer.** Cover from the
## target is also cover from your own shot -- this game's cover is binary line
## of sight, with no peeking out. "Take cover, then Scald" measured 54.6% of
## ticks in cover and 10/20 wins against 20/20, the pawn standing behind a
## pillar it could not shoot past until the tick limit. The pairing has no
## satisfying position, so the row steps aside instead of idling out the fight.
func test_a_line_of_sight_action_makes_the_row_step_aside() -> void:
	var s := _situation(_plan_with(&"geyser_scald"), Vector2(-200.0, 200.0), Vector2(-200.0, 0.0),
		[Terrain.make(Terrain.Kind.PILLAR, PILLAR_AT)])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	assert_true(ActionLibrary.get_action(&"geyser_scald").requires_line_of_sight,
		"fixture check: this test is meaningless if Scald stops needing a clear line")
	assert_true(PlanInterpreter.decide(state, me) == null,
		"cover and a line-of-sight shot cannot both be had; the row must let the next one try")


## The complement, and the reason the rule is about line of sight rather than
## about actions in general: a self-buff needs no line to anything, so "move
## into cover and raise your shield" is exactly the plan that does work.
func test_a_self_buff_still_fires_from_cover() -> void:
	assert_false(ActionLibrary.get_action(&"warrior_block").requires_line_of_sight,
		"fixture check: Directional Block must not need a clear line")


## Design question 2, answered yes: an ally's raised shield is cover. This is
## the case #315 measured, 64,602 ally-ticks already spent in the shield's
## shadow by accident across 452 of 800 fights, and never once on purpose.
func test_an_allys_raised_shield_counts_as_cover() -> void:
	var s := _situation(_plan_with(), Vector2(400.0, 200.0), Vector2(0.0, -200.0), [])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var foe: CombatUnit = s[2]

	var ally := CombatUnit.new()
	ally.id = 900
	ally.team = me.team
	ally.position = Vector2(0.0, 0.0)
	ally.hp_max = 100
	ally.hp = 100
	ally.facing = (foe.position - ally.position).normalized()
	ally.statuses[CG.Status.SHIELDING] = 300
	state.units.append(ally)

	assert_false(CombatSim.shot_would_be_shielded(state, me.team, foe.team, foe.position, me.position),
		"fixture check: this pawn must start OUT of the shield's shadow, or moving into it proves nothing")
	var intent := PlanInterpreter.decide(state, me)
	assert_not_null(intent, "an ally's shield is the only cover in this room and it must be found")
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_true(CombatSim.shot_would_be_shielded(state, me.team, foe.team, foe.position, intent.destination),
		"the destination must be a spot the shield actually covers, got %s" % intent.destination)


## Already standing in the shield's shadow: the pawn has arrived and holds.
##
## Written because neutralising the shield half of `in_cover_from` broke no
## test -- `_cover_spot` covered for it. This is the case #315 measured, where
## allies are in the shadow 64,602 ticks already; the block must recognise it
## rather than walking them somewhere else.
func test_a_pawn_already_behind_an_allys_shield_holds_still() -> void:
	var s := _situation(_plan_with(), Vector2(0.0, 100.0), Vector2(0.0, -200.0), [])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var foe: CombatUnit = s[2]

	var ally := CombatUnit.new()
	ally.id = 900
	ally.team = me.team
	ally.position = Vector2(0.0, 0.0)
	ally.hp_max = 100
	ally.hp = 100
	ally.facing = (foe.position - ally.position).normalized()
	ally.statuses[CG.Status.SHIELDING] = 300
	state.units.append(ally)

	assert_true(CombatSim.shot_would_be_shielded(state, me.team, foe.team, foe.position, me.position),
		"fixture check: this pawn should start inside the shield's shadow")
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.IDLE, "behind the shield is arrived, not keep walking")
	assert_eq(intent.source_plan, &"cover_test")


## The same ally with no shield raised is not cover, so the room is empty again.
## Without this, the test above passes on a block that walks toward any ally.
func test_the_same_ally_without_a_shield_is_not_cover() -> void:
	var s := _situation(_plan_with(), Vector2(400.0, 200.0), Vector2(0.0, -200.0), [])
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var foe: CombatUnit = s[2]

	var ally := CombatUnit.new()
	ally.id = 900
	ally.team = me.team
	ally.position = Vector2(0.0, 0.0)
	ally.hp_max = 100
	ally.hp = 100
	ally.facing = (foe.position - ally.position).normalized()
	state.units.append(ally)

	assert_true(PlanInterpreter.decide(state, me) == null,
		"a bare ally is not cover; only a raised shield is")


## Determinism, which this project treats as sacred. Two pillars equally far
## away must resolve the same way every time rather than reaching for the rng.
func test_two_equal_pieces_of_cover_resolve_deterministically() -> void:
	var features := [
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-130.0, -40.0, 60.0, 80.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(70.0, -40.0, 60.0, 80.0)),
	]
	var first := Vector2.INF
	for i in 3:
		var s := _situation(_plan_with(), Vector2(0.0, 240.0), Vector2(0.0, -240.0), features)
		var state: CombatState = s[0]
		var me: CombatUnit = s[1]
		var intent := PlanInterpreter.decide(state, me)
		assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
		if i == 0:
			first = intent.destination
		else:
			assert_eq(intent.destination, first, "same room, same answer")


## The op is readable in the plan editor, the thing #97 found broken for
## `keep_distance`. A block the player cannot read is one they cannot use.
func test_the_cover_op_is_readable_and_editable() -> void:
	assert_eq(BlockCatalog.movement(&"move_into_cover").describe(), "move into cover from the target")
	assert_true(BlockCatalog.MOVEMENT_OPS.has(&"move_into_cover"))
