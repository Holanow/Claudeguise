extends "res://Tests/TestCase.gd"


## Issue 97's recorded constraint, decided: a movement block chooses where the
## pawn stands, it does not choose what the action is aimed at.

func _blocks(targeting_op: StringName, action_id: StringName, hold: float) -> Array[PlanBlock]:
	var targeting := PlanFixtures.block(targeting_op)
	var movement := PlanFixtures.block(&"keep_distance", {"range_units": hold})
	var action := PlanFixtures.block(&"use_action", {"action_id": action_id})
	return [targeting, movement, action]


## One pawn of `class_id` carrying `blocks`, one living enemy `foe_at` away
## **edge to edge**, which is what `keep_distance` measures since issue 642, every
## other enemy switched off. `alive` is a stored bool, so it is set directly --
## `hp = 0` does not kill a unit (issue 325).
func _situation(class_id: StringName, blocks: Array[PlanBlock], foe_at: Vector2) -> Array:
	var pawn := PawnFactory.make_starter_pawn(class_id, &"p0", "P")
	var plan := Plan.new()
	plan.id = &"aim_test"
	plan.display_name = "Aim"
	plan.blocks = blocks
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
	me.position = Vector2.ZERO
	me.resource = me.resource_max
	foe.position = foe_at if foe_at.length() < 0.0001 		else foe_at + foe_at.normalized() * (me.radius + foe.radius)
	return [state, me, foe]


## **The constraint, and it is why this exists.** `keep_distance{0}` plus
## Immolate reads as "charge in and burn" and used to be "charge in and idle":
## a self-targeted action states `range_units == 0.0`, so measuring it against
## the focused enemy refused it at every distance above zero.
func test_a_movement_block_can_carry_a_self_targeted_action() -> void:
	var s := _situation(&"abomination", _blocks(&"target_nearest_enemy", &"abomination_immolate", 0.0), Vector2(5.0, 0.0))
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_not_null(intent, "the block idled here before this decision")
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.action_id, &"abomination_immolate")
	assert_eq(intent.target_id, me.id,
		"a self-targeted action lands on the caster, not on whoever the plan focused")


## The negative half, and the reason this is not "skip the range check". Aiming
## is not reach: an enemy-targeted action in a movement block is still refused
## when the enemy is outside its range, and the block holds position instead.
func test_a_movement_block_still_refuses_an_out_of_reach_enemy_action() -> void:
	var s := _situation(&"abomination", _blocks(&"target_nearest_enemy", &"abomination_grapple", 300.0), Vector2(300.0, 0.0))
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.IDLE,
		"a 45-unit grapple cannot reach 300 units; the block holds position and says so")


## The same rule outside a movement block, because there is one rule and not
## two. A self-buff under enemy targeting used to fall through to
## `DefaultBehavior`, which is a pawn acting on a rule written in no plan.
func test_a_self_buff_under_enemy_targeting_fires_rather_than_falling_through() -> void:
	var targeting := PlanFixtures.block(&"target_nearest_enemy")
	var action := PlanFixtures.block(&"use_action", {"action_id": &"warrior_taunt"})
	var blocks: Array[PlanBlock] = [targeting, action]
	var s := _situation(&"warrior", blocks, Vector2(400.0, 0.0))
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var intent := PlanInterpreter.decide(state, me)
	assert_not_null(intent, "the plan named an action the pawn can cast; it must not hand the tick away")
	assert_eq(intent.action_id, &"warrior_taunt")
	assert_eq(intent.target_id, me.id)
	assert_eq(intent.source_plan, &"aim_test",
		"the log has to be able to name the plan that cast it")


## An enemy-targeted action is unaffected: it is still aimed at the focus and
## still measured against it. This is the whole rest of the game.
func test_an_enemy_targeted_action_is_still_aimed_at_the_focus() -> void:
	var s := _situation(&"abomination", _blocks(&"target_nearest_enemy", &"abomination_grapple", 40.0), Vector2(40.0, 0.0))
	var state: CombatState = s[0]
	var me: CombatUnit = s[1]
	var foe: CombatUnit = s[2]
	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.target_id, foe.id, "an enemy-targeted action must still point at the enemy")
