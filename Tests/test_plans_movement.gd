extends "res://Tests/TestCase.gd"


## Issue 97: kiting as a MOVEMENT block the player controls. OWNER: heron.

const RANGE := 120.0

func _movement(range_units: float) -> PlanBlock:
	var b := PlanFixtures.block(&"keep_distance", {"range_units": range_units})
	return b


func _targeting() -> PlanBlock:
	var b := PlanFixtures.block(&"target_nearest_enemy")
	return b


func _action(action_id: StringName) -> PlanBlock:
	var b := PlanFixtures.block(&"use_action", {"action_id": action_id})
	return b


func _plan(blocks: Array[PlanBlock], id: StringName = &"kite_test") -> Plan:
	var p := Plan.new()
	p.id = id
	p.display_name = "Kite"
	p.blocks = blocks
	return p


## A two-unit fight built by hand: one player pawn carrying `plan`, one enemy at
## `enemy_at`. Real `CombatSim.build` so the units are real, then the enemy is
## moved to the distance the case is about.
func _situation(plan: Plan, enemy_at: Vector2, class_id: StringName = &"geysermancer") -> Array:
	var pawn := PawnFactory.make_starter_pawn(class_id, &"p0", "P")
	pawn.plans = [plan]
	var party: Array[PawnData] = [pawn]
	var state := CombatSim.build(party, Registry.get_encounter(&"floor1_ghoul_den"), 1, SimDeps.new())
	var me: CombatUnit = null
	var foe: CombatUnit = null
	for u in state.units:
		if u.team == CG.Team.PLAYER and me == null:
			me = u
		elif u.team == CG.Team.ENEMY and foe == null:
			foe = u
	# Drop every other enemy so "nearest enemy" is unambiguous. Issue 325:
	# `alive` is a stored bool that only the kill path clears, so `hp = 0` on
	# its own left every one of them alive and this comment was false.
	for u in state.units:
		if u.team == CG.Team.ENEMY and u != foe:
			u.hp = 0
			u.alive = false
	me.position = Vector2.ZERO
	foe.position = enemy_at
	## Issue 325: the line above used to be a comment claiming this, while every
	## other enemy stayed alive. It is an assertion now, so the claim cannot go
	## quietly false again.
	assert_eq(state.living(CG.Team.ENEMY).size(), 1,
		"the fixture promises one living enemy and left %d" % state.living(CG.Team.ENEMY).size())
	assert_eq(state.living(CG.Team.ENEMY)[0].id, foe.id,
		"the one living enemy must be the one the case is about")
	return [state, me, foe]


## Too close: the pawn backs off, and it backs off along the line away from the
## target rather than in some fixed direction, so the block works from any side.
func test_keep_distance_retreats_when_the_target_is_too_close() -> void:
	var plan := _plan([_targeting(), _movement(RANGE), _action(&"geyser_spout")])
	var s := _situation(plan, Vector2(40.0, 0.0))
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_not_null(intent, "a movement block must produce an intent, not fall through")
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_eq(intent.source_plan, &"kite_test", "the log must be able to name the plan that moved the pawn")
	assert_true(intent.destination.x < me.position.x,
		"the enemy is to the right, so retreating means moving left, got %s" % intent.destination)
	assert_almost_eq(intent.destination.distance_to(Vector2(40.0, 0.0)), RANGE, 1.0,
		"a retreat should end at the distance the block asked for")


## The same block from the opposite side, because a retreat that only works
## when the enemy is to the right is a fixed direction wearing a disguise.
## This is the case that killed the player's own "move 25 units left" idea.
func test_keep_distance_works_from_any_side() -> void:
	var plan := _plan([_targeting(), _movement(RANGE), _action(&"geyser_spout")])
	var s := _situation(plan, Vector2(0.0, -40.0))
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_true(intent.destination.y > me.position.y,
		"the enemy is above, so retreating means moving down, got %s" % intent.destination)


## Too far: the same op closes, which is why "close to melee" needs no second
## op. `keep_distance{range: 0}` is a charge.
func test_keep_distance_closes_when_the_target_is_too_far() -> void:
	var plan := _plan([_targeting(), _movement(0.0), _action(&"geyser_spout")])
	var s := _situation(plan, Vector2(400.0, 0.0))
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_true(intent.destination.distance_to(Vector2(400.0, 0.0)) < 400.0,
		"range 0 means close all the way, got %s" % intent.destination)


## Standing where the player asked, with a firing action: attack. This is the
## "kite and attack" block the player asked for, and it is one block plus the
## action rather than a special kind.
func test_at_the_requested_distance_the_pawn_fires() -> void:
	var plan := _plan([_targeting(), _movement(RANGE), _action(&"geyser_spout")])
	var s := _situation(plan, Vector2(RANGE, 0.0))
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.action_id, &"geyser_spout")
	assert_eq(intent.source_plan, &"kite_test")


## **The hysteresis test, and the reason the band exists.**
##
## Issue 94 turned up a two-tick limit cycle: a pawn between two rules that
## disagreed stepped three units, the situation flipped, it stepped back, and it
## did that for 2400 ticks without firing once. Positions were exactly period-2.
func test_every_distance_inside_the_band_holds_still() -> void:
	var plan := _plan([_targeting(), _movement(RANGE), _action(&"warrior_execute")])
	for offset in [-14.0, -7.0, 0.0, 7.0, 14.0]:
		var s := _situation(plan, Vector2(RANGE + offset, 0.0))
		var state: CombatState = s[0]
		var me: CombatUnit = s[1]
		var intent := PlanInterpreter.decide(state, me)
		assert_eq(intent.kind, CG.IntentKind.IDLE,
			"at %0.0f units from a requested %0.0f the pawn should have arrived, not moved" % [RANGE + offset, RANGE])


## The negative half, and the one that would catch a band so wide the block
## stops meaning anything: outside the band, the pawn does move.
func test_just_outside_the_band_the_pawn_moves() -> void:
	var plan := _plan([_targeting(), _movement(RANGE), _action(&"geyser_spout")])
	for offset in [-40.0, 40.0]:
		var s := _situation(plan, Vector2(RANGE + offset, 0.0))
		var state: CombatState = s[0]
		var me: CombatUnit = s[1]
		var intent := PlanInterpreter.decide(state, me)
		assert_eq(intent.kind, CG.IntentKind.MOVE_TO,
			"at %0.0f units from a requested %0.0f the pawn should reposition" % [RANGE + offset, RANGE])


## **The issue 98 assertion: a movement block is never silently overruled.**
##
## The action here cannot fire -- `warrior_execute` costs Rage the pawn does not
## have and is not even the pawn's own action. Before this change every such
## gate returned null from `_run_blocks`, which hands the tick to
## `DefaultBehavior` and lets hidden code decide where the pawn stands. With a
## movement block the plan must keep the decision: hold, and say which plan
## said so.
func test_a_movement_block_never_falls_through_when_the_action_cannot_fire() -> void:
	var plan := _plan([_targeting(), _movement(RANGE), _action(&"warrior_execute")])
	var s := _situation(plan, Vector2(RANGE, 0.0))
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_not_null(intent, "the plan owns the position; it must not hand the tick to DefaultBehavior")
	assert_eq(intent.kind, CG.IntentKind.IDLE)
	assert_eq(intent.source_plan, &"kite_test",
		"an idle with no plan on it is exactly the unexplained standing-still issue 98 objects to")


## A movement block with no action at all is a legal plan: "stay 120 away" is a
## complete instruction. It should position and not error.
func test_a_movement_block_alone_is_a_complete_plan() -> void:
	var plan := _plan([_targeting(), _movement(RANGE)])
	var s := _situation(plan, Vector2(30.0, 0.0))
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)


## Determinism, which this project treats as sacred and which a movement rule
## is well placed to break: two units on top of each other have no "away"
## direction, and reaching for the rng there would make a fight unreproducible.
func test_a_target_on_top_of_the_pawn_is_deterministic() -> void:
	var plan := _plan([_targeting(), _movement(RANGE), _action(&"geyser_spout")])
	var first := Vector2.ZERO
	for i in 3:
		var s := _situation(plan, Vector2.ZERO)
		var state: CombatState = s[0]
		var me: CombatUnit = s[1]
		var intent := PlanInterpreter.decide(state, me)
		assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
		if i == 0:
			first = intent.destination
		else:
			assert_eq(intent.destination, first, "same situation must give the same destination")


## Plans without a movement block behave exactly as they did. The whole
## interpreter runs on every pawn every tick, so the blast radius of getting
## this wrong is the entire game.
func test_plans_without_a_movement_block_are_unchanged() -> void:
	var plan := _plan([_targeting(), _action(&"geyser_spout")])
	var s := _situation(plan, Vector2(1000.0, 0.0))
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_true(intent == null,
		"an out-of-range action with no movement block must still fall through to DefaultBehavior")
