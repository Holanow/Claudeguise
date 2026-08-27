extends "res://Tests/TestCase.gd"


## Issue 97's automatic kite band, **deleted in #544**. Issue 97 stopped it
## walking a unit away from a shot it could take when the threat was faster;
## #544 measured that the speed edge never bought the shot back either, so the
## rule is now simply "in range, fire". Holding distance is `keep_distance`,
## which the rest of this file exercises.

func _immobile_dummy(id: int, team: CG.Team, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.position = pos
	u.hp_max = 1000000
	u.hp = u.hp_max
	u.move_speed = 0.0
	u.actions = []
	return u

func _stalker(at: Vector2 = Vector2.ZERO) -> CombatUnit:
	var def := Registry.get_enemy(&"stalker")
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.enemy_id = &"stalker"
	u.position = at
	u.hp_max = 1000
	u.hp = u.hp_max
	u.resource_kind = def.resource_kind
	u.resource_max = def.resource_max
	u.resource = def.resource_max
	u.move_speed = def.move_speed
	u.radius = def.radius
	u.actions = def.actions.duplicate()
	return u

func _decide(unit: CombatUnit, enemy_at: float) -> Intent:
	var enemy := _immobile_dummy(1, CG.Team.ENEMY, Vector2(enemy_at, 0.0))
	var state := CombatState.new(0)
	state.units.append(unit)
	state.units.append(enemy)
	return DefaultBehavior.decide(state, unit)


## **The defect, and it is heron's measurement in commit a6750e8 stated as one
## decision:** the Rat King "is in range and forbidden to fire, which is worse".
func test_a_ranged_unit_that_cannot_outrun_the_threat_fires_instead_of_fleeing() -> void:
	var stalker := _stalker()
	var chaser := _immobile_dummy(1, CG.Team.ENEMY, Vector2(60.0, 0.0))
	chaser.move_speed = stalker.move_speed + 1.0
	var state := CombatState.new(0)
	state.units.append(stalker)
	state.units.append(chaser)
	var intent := DefaultBehavior.decide(state, stalker)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION,
		"60 units is inside the 132-unit kite floor, but the threat is faster; fleeing gives up the shot for nothing")
	assert_eq(intent.target_id, 1)


## #544: the case the band *was* written for now fires too. A speed edge used to
## send this unit backwards forever, because the ticks a shot costs give back
## more ground than the edge buys.
func test_the_same_unit_fires_at_something_slower_instead_of_backing_off() -> void:
	var stalker := _stalker()
	var chaser := _immobile_dummy(1, CG.Team.ENEMY, Vector2(60.0, 0.0))
	chaser.move_speed = stalker.move_speed - 1.0
	var state := CombatState.new(0)
	state.units.append(stalker)
	state.units.append(chaser)
	var intent := DefaultBehavior.decide(state, stalker)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION,
		"the fallback has no automatic retreat left; a unit in range fires whatever the speeds are")
	assert_eq(intent.target_id, 1)


## The far edge of the band is a different rule and is untouched: firing at the
## rim of range whiffs against anything that steps back during the wind-up.
func test_a_unit_beyond_its_commit_distance_still_closes() -> void:
	var stalker := _stalker()
	## Issue 642: the commit window is edge to edge, so the two bodies' radii
	## have to be clear of it as well as the window itself.
	var intent := _decide(stalker, 260.0)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_true(intent.destination.distance_to(Vector2(260.0, 0.0)) < 260.0,
		"beyond 0.85 of its reach the unit approaches, got %s" % intent.destination)


## Issue 97's recorded constraint, now decided: a MOVEMENT block measures its
## distance from the focused enemy, and a self-targeted action inside it is
## still cast on the caster instead of being refused for having no reach.
func test_a_movement_block_can_carry_a_self_targeted_action() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"abomination", &"a0", "A")
	var plan := Plan.new()
	plan.id = &"kite_and_burn"
	plan.display_name = "Immolate up close"
	var targeting := PlanFixtures.block(&"target_nearest_enemy")
	var movement := PlanFixtures.block(&"keep_distance", {"range_units": 0.0})
	var action := PlanFixtures.block(&"use_action", {"action_id": &"abomination_immolate"})
	plan.blocks = [targeting, movement, action]
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
	foe.position = Vector2(5.0, 0.0)

	var intent := PlanInterpreter.decide(state, me)
	assert_not_null(intent, "the block idled here before issue 97 decided this")
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.action_id, &"abomination_immolate")
	assert_eq(intent.target_id, me.id, "a self-targeted action lands on the caster, not on whoever the plan focused")


## The negative half: aiming is not the same as reach. An enemy-targeted action
## in a movement block is still refused when the enemy is outside its range.
func test_a_movement_block_still_refuses_an_out_of_reach_enemy_action() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"abomination", &"a1", "A")
	var plan := Plan.new()
	plan.id = &"grapple_from_afar"
	plan.display_name = "Grapple"
	var targeting := PlanFixtures.block(&"target_nearest_enemy")
	var movement := PlanFixtures.block(&"keep_distance", {"range_units": 300.0})
	var action := PlanFixtures.block(&"use_action", {"action_id": &"abomination_grapple"})
	plan.blocks = [targeting, movement, action]
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
	foe.position = Vector2(300.0, 0.0)

	var intent := PlanInterpreter.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.IDLE,
		"a 45-unit grapple cannot reach 300 units; the block holds position and says so")


## The op names itself in the plan editor. An unnamed op renders as
## "unknown op 'keep_distance'" on the one screen this issue exists to fix.
func test_the_movement_op_has_a_player_facing_sentence() -> void:
	assert_eq(PlanFixtures.block(&"keep_distance", {"range_units": 120.0}).describe(), "hold 120 units from the target, on ground that does not harm")
	assert_eq(PlanFixtures.block(&"keep_distance", {"range_units": 0.0}).describe(), "close to the target")
	for op in BlockCatalog.MOVEMENT_OPS:
		assert_true(BlockCatalog.movement(op).describe() != "", "'%s' has no sentence" % op)
