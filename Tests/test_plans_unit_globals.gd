extends "res://Tests/TestCase.gd"


## Issue 755/756: UnitGlobals and the standing preferences it reads. Direct
## decide() calls for target/posture (precise, single-decision), a real
## CombatSim.step loop for avoid_hazards (the effect is in _resolve_move, not
## in decide()). No test here runs a fight -- CombatSim.build only.

func _unit(id: int, team: CG.Team, pawn: PawnData, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.pawn = pawn
	u.position = pos
	u.hp_max = 1000000
	u.hp = u.hp_max
	u.move_speed = 1.0
	u.actions = [&"warrior_strike"]
	return u

func _party_with_globals(pawn: PawnData) -> Array[PawnData]:
	return [pawn]

func test_target_preference_farthest_overrides_the_nearest_default() -> void:
	var state := CombatState.new(1)
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"p0", "P")
	pawn.target_preference = UnitGlobals.TARGET_FARTHEST
	var me := _unit(0, CG.Team.PLAYER, pawn, Vector2.ZERO)
	var near := _unit(1, CG.Team.ENEMY, null, Vector2(100.0, 0.0))
	near.enemy_id = &"goblin"
	var far := _unit(2, CG.Team.ENEMY, null, Vector2(500.0, 0.0))
	far.enemy_id = &"goblin"
	state.units = [me, near, far]

	var intent := DefaultBehavior.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO, "both are out of melee range")
	assert_eq(intent.destination, far.position, "farthest preference must chase the far one, not the near one")

func test_target_preference_default_is_nearest_unchanged() -> void:
	var state := CombatState.new(1)
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"p0", "P")
	var me := _unit(0, CG.Team.PLAYER, pawn, Vector2.ZERO)
	var near := _unit(1, CG.Team.ENEMY, null, Vector2(100.0, 0.0))
	near.enemy_id = &"goblin"
	var far := _unit(2, CG.Team.ENEMY, null, Vector2(500.0, 0.0))
	far.enemy_id = &"goblin"
	state.units = [me, near, far]

	var intent := DefaultBehavior.decide(state, me)
	assert_eq(intent.destination, near.position, "an unset preference must still chase the nearest one")

func test_stand_near_ally_redirects_a_chasing_walk_to_the_named_ally() -> void:
	var state := CombatState.new(1)
	var guard := PawnFactory.make_starter_pawn(&"warrior", &"guard", "Guard")
	var charge := PawnFactory.make_starter_pawn(&"priest", &"charge", "Charge")
	guard.posture = UnitGlobals.POSTURE_STAND_NEAR_ALLY
	guard.stand_near_ally_id = charge.id

	var me := _unit(0, CG.Team.PLAYER, guard, Vector2(-400.0, 0.0))
	var ally := _unit(1, CG.Team.PLAYER, charge, Vector2(-400.0, 300.0))
	var foe := _unit(2, CG.Team.ENEMY, null, Vector2(400.0, 0.0))
	foe.enemy_id = &"goblin"
	state.units = [me, ally, foe]

	var intent := DefaultBehavior.decide(state, me)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
	assert_eq(intent.destination, ally.position, "stand_near_ally must walk toward the ally, not the enemy")

func test_stand_near_ally_falls_back_to_seek_enemy_when_the_ally_is_dead() -> void:
	var state := CombatState.new(1)
	var guard := PawnFactory.make_starter_pawn(&"warrior", &"guard", "Guard")
	var charge := PawnFactory.make_starter_pawn(&"priest", &"charge", "Charge")
	guard.posture = UnitGlobals.POSTURE_STAND_NEAR_ALLY
	guard.stand_near_ally_id = charge.id

	var me := _unit(0, CG.Team.PLAYER, guard, Vector2(-400.0, 0.0))
	var ally := _unit(1, CG.Team.PLAYER, charge, Vector2(-400.0, 300.0))
	ally.alive = false
	var foe := _unit(2, CG.Team.ENEMY, null, Vector2(400.0, 0.0))
	foe.enemy_id = &"goblin"
	state.units = [me, ally, foe]

	var intent := DefaultBehavior.decide(state, me)
	assert_eq(intent.destination, foe.position, "a dead ally must fall back to chasing the enemy, not stand at the corpse")

func test_stand_near_ally_falls_back_on_a_dangling_id() -> void:
	var state := CombatState.new(1)
	var guard := PawnFactory.make_starter_pawn(&"warrior", &"guard", "Guard")
	guard.posture = UnitGlobals.POSTURE_STAND_NEAR_ALLY
	guard.stand_near_ally_id = &"nobody_in_this_fight"

	var me := _unit(0, CG.Team.PLAYER, guard, Vector2(-400.0, 0.0))
	var foe := _unit(1, CG.Team.ENEMY, null, Vector2(400.0, 0.0))
	foe.enemy_id = &"goblin"
	state.units = [me, foe]

	var intent := DefaultBehavior.decide(state, me)
	assert_eq(intent.destination, foe.position, "a dangling id must fall back to chasing the enemy")

func test_a_pawn_cannot_name_itself() -> void:
	var state := CombatState.new(1)
	var guard := PawnFactory.make_starter_pawn(&"warrior", &"guard", "Guard")
	guard.posture = UnitGlobals.POSTURE_STAND_NEAR_ALLY
	guard.stand_near_ally_id = guard.id

	var me := _unit(0, CG.Team.PLAYER, guard, Vector2(-400.0, 0.0))
	var foe := _unit(1, CG.Team.ENEMY, null, Vector2(400.0, 0.0))
	foe.enemy_id = &"goblin"
	state.units = [me, foe]

	assert_eq(UnitGlobals.stand_near_ally_unit(state, me), null, "naming oneself must resolve to no ally, not a self-loop")

## Issue 756: the enemy-side reader. `EnemyLibrary.get_enemy` returns null for
## an id nothing registers, and every accessor's fallback is the pawn-side
## default -- proving the branch exists and cannot crash without mutating a
## real, shared EnemyDef in the registry.
func test_enemy_side_reader_defaults_safely_off_an_unknown_enemy_id() -> void:
	var u := CombatUnit.new()
	u.pawn = null
	u.enemy_id = &"not_a_real_enemy_id"
	assert_true(UnitGlobals.avoid_hazards(u))
	assert_eq(UnitGlobals.target_preference(u), UnitGlobals.TARGET_NEAREST)
	assert_eq(UnitGlobals.posture(u), UnitGlobals.POSTURE_SEEK_ENEMY)
	assert_eq(UnitGlobals.stand_near_ally_id(u), &"")

## The two rules together: two allies each naming the other cannot loop,
## because each side only ever reads the other's current position -- neither
## call re-enters target or posture logic for the other.
func test_two_pawns_naming_each_other_do_not_loop() -> void:
	var state := CombatState.new(1)
	var a := PawnFactory.make_starter_pawn(&"warrior", &"a", "A")
	var b := PawnFactory.make_starter_pawn(&"priest", &"b", "B")
	a.posture = UnitGlobals.POSTURE_STAND_NEAR_ALLY
	a.stand_near_ally_id = b.id
	b.posture = UnitGlobals.POSTURE_STAND_NEAR_ALLY
	b.stand_near_ally_id = a.id

	var ua := _unit(0, CG.Team.PLAYER, a, Vector2(-400.0, 0.0))
	var ub := _unit(1, CG.Team.PLAYER, b, Vector2(-400.0, 300.0))
	var foe := _unit(2, CG.Team.ENEMY, null, Vector2(400.0, 0.0))
	foe.enemy_id = &"goblin"
	state.units = [ua, ub, foe]

	var intent_a := DefaultBehavior.decide(state, ua)
	var intent_b := DefaultBehavior.decide(state, ub)
	assert_eq(intent_a.destination, ub.position)
	assert_eq(intent_b.destination, ua.position)

## avoid_hazards's effect is in CombatSim._resolve_move, not in decide(). A
## real step loop through a hazard band standing directly in the walker's
## path -- `_avoid_hazard` only prefers a clear route "when one exists that
## still makes progress" (its own comment), not an absolute guarantee, so
## the honest comparison is *when* fire is first touched, not *whether*.
func _first_fire_contact_tick(avoid: bool) -> int:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"p0", "P")
	pawn.avoid_hazards = avoid
	var state := CombatSim.build([pawn], RoomLibrary.get_room(&"floor1_ghoul_den"), 1, SimDeps.new())
	var me: CombatUnit = null
	for u in state.units:
		if u.team == CG.Team.PLAYER:
			me = u
	var foe: CombatUnit = null
	for u in state.units:
		if u.team == CG.Team.ENEMY:
			if foe == null:
				foe = u
			else:
				u.alive = false
	me.position = Vector2(-300.0, 0.0)
	me.hp = me.hp_max
	foe.position = Vector2(400.0, 0.0)
	var band := Terrain.hazard(Rect2(-100.0, -270.0, 200.0, 540.0), 2, CG.DamageType.FIRE)
	state.grid.stamp_features([band])

	for i in 400:
		CombatSim.step(state)
		if CombatSim.standing_harms(state, me.position):
			return i
	return -1

func test_avoid_hazards_false_reaches_fire_no_later_than_the_default() -> void:
	var disabled_tick := _first_fire_contact_tick(false)
	var default_tick := _first_fire_contact_tick(true)
	assert_true(disabled_tick >= 0, "avoid_hazards=false, walking straight at the band, must touch it")
	assert_true(default_tick < 0 or disabled_tick <= default_tick,
		"disabling avoidance must not detour *more* than the default: disabled=%d default=%d" % [disabled_tick, default_tick])
