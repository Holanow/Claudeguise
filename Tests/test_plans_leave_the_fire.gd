extends "res://Tests/TestCase.gd"


## Issue 338: a unit that has decided to do nothing steps out of the fire.
## The player asked for it after a blind playtester watched a Siege Master take
## ground fire for twenty seconds without moving.

const FIRE := Rect2(-60.0, -60.0, 120.0, 120.0)

func _fire() -> Array:
	return [Terrain.hazard(FIRE, 3, CG.DamageType.FIRE)]

## A decorative hazard: no damage, no status. `_hazard_harms` ignores it and so
## must this, or every painted puddle starts herding pawns around.
func _paint() -> Array:
	return [Terrain.hazard(FIRE, 0, CG.DamageType.FIRE)]

func _unit_at(pos: Vector2, team: CG.Team, actions: Array[StringName]) -> CombatUnit:
	var u := CombatUnit.new()
	u.pawn = PawnData.new()
	u.team = team
	u.position = pos
	u.hp_max = 100
	u.hp = 100
	u.move_speed = 3.0
	u.resource_kind = CG.ResourceKind.RAGE
	u.resource_max = 100
	u.resource = 100
	u.actions = actions
	return u

## `unit` alone against one far-off enemy, on `features`.
func _state(unit: CombatUnit, features: Array, foe_at: Vector2 = Vector2(2000.0, 0.0)) -> CombatState:
	var state := CombatState.new(0)
	unit.id = 0
	state.units.append(unit)
	var foe := _unit_at(foe_at, CG.Team.ENEMY, [])
	foe.pawn = null
	foe.id = 1
	foe.move_speed = 0.0
	state.units.append(foe)
	state.terrain = features
	return state


## The case the player reported: nothing to do, standing in fire.
func test_a_unit_with_nothing_to_do_steps_off_the_fire() -> void:
	var u := _unit_at(Vector2.ZERO, CG.Team.PLAYER, [])
	var state := _state(u, _fire())
	var intent := DefaultBehavior.decide(state, u)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO, "standing still in fire is the one case this replaces")
	assert_false(CombatSim.standing_harms(state, intent.destination),
		"the destination must be off the fire, got %s" % intent.destination)


## **The negative half, and the one that keeps this from becoming the automatic
## kiting mistake again.** A unit with something to do keeps doing it: the
## branch replaces an IDLE intent and nothing else.
func test_a_unit_that_can_attack_does_not_flee_the_fire() -> void:
	var u := _unit_at(Vector2.ZERO, CG.Team.PLAYER, [&"warrior_strike"])
	var state := _state(u, _fire(), Vector2(20.0, 0.0))
	var intent := DefaultBehavior.decide(state, u)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION,
		"an enemy in reach outranks the fire; this branch only replaces standing still")


## Off the fire and idle: it stays put. Without this the branch could be a unit
## that wanders every tick it has nothing to do.
func test_a_unit_standing_on_clean_floor_still_idles() -> void:
	var u := _unit_at(Vector2(300.0, 0.0), CG.Team.PLAYER, [])
	var state := _state(u, _fire())
	assert_eq(DefaultBehavior.decide(state, u).kind, CG.IntentKind.IDLE,
		"there is nothing to step away from here")


## A hazard that costs nothing is not a reason to move. This is the rule
## `_hazard_harms` already encodes, called rather than restated.
func test_a_harmless_puddle_is_not_fled() -> void:
	var u := _unit_at(Vector2.ZERO, CG.Team.PLAYER, [])
	var state := _state(u, _paint())
	assert_eq(DefaultBehavior.decide(state, u).kind, CG.IntentKind.IDLE,
		"a decorative hazard harms nobody and must not herd anyone")


## A unit that cannot move stays where it is rather than emitting a move it can
## never make. The Siege Engine is the one unit in the game at move_speed 0.
func test_an_immobile_unit_in_fire_does_not_pretend_to_move() -> void:
	var u := _unit_at(Vector2.ZERO, CG.Team.PLAYER, [])
	u.move_speed = 0.0
	var state := _state(u, _fire())
	assert_eq(DefaultBehavior.decide(state, u).kind, CG.IntentKind.IDLE,
		"an immobile unit cannot step off anything")


## Fire that fills the whole reachable area leaves nowhere better to stand, and
## the unit must idle rather than walk to a spot just as bad.
func test_nowhere_safe_means_stay_put() -> void:
	var u := _unit_at(Vector2.ZERO, CG.Team.PLAYER, [])
	var huge := Rect2(-CG.ARENA_HALF_WIDTH * 2.0, -CG.ARENA_HALF_HEIGHT * 2.0,
		CG.ARENA_HALF_WIDTH * 4.0, CG.ARENA_HALF_HEIGHT * 4.0)
	var state := _state(u, [Terrain.hazard(huge, 3, CG.DamageType.FIRE)])
	assert_eq(DefaultBehavior.decide(state, u).kind, CG.IntentKind.IDLE,
		"every exit is still on fire, so there is no step worth taking")


## Determinism, which this project treats as sacred. The unit sits dead centre,
## so all four edges are equidistant and the answer must still be the same one
## every time rather than reaching for the rng.
func test_four_equidistant_exits_resolve_deterministically() -> void:
	var first := Vector2.INF
	for i in 3:
		var u := _unit_at(Vector2.ZERO, CG.Team.PLAYER, [])
		var state := _state(u, _fire())
		var intent := DefaultBehavior.decide(state, u)
		assert_eq(intent.kind, CG.IntentKind.MOVE_TO)
		if i == 0:
			first = intent.destination
		else:
			assert_eq(intent.destination, first, "same fire, same exit")


## Enemies get the branch too, and this records that decision rather than
## leaving it to be discovered. `DefaultBehavior` is one shared fallback and a
## rule that applied to one team only would be a hidden rule of its own.
func test_an_enemy_with_nothing_to_do_also_steps_off() -> void:
	var e := _unit_at(Vector2.ZERO, CG.Team.ENEMY, [])
	e.pawn = null
	var state := CombatState.new(0)
	e.id = 0
	state.units.append(e)
	var foe := _unit_at(Vector2(2000.0, 0.0), CG.Team.PLAYER, [])
	foe.id = 1
	foe.move_speed = 0.0
	state.units.append(foe)
	state.terrain = _fire()
	var intent := DefaultBehavior.decide(state, e)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO, "the fallback is shared; so is this branch")
