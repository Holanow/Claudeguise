extends "res://Tests/TestCase.gd"


## ISSUE 255. **You cannot hide behind a pillar you are standing in.**
##
## Filed as a positioning defect -- "a unit may not end a step inside a blocking
## rect" -- and it is not one. `floor1_cover` has no blocking terrain at all:
## every feature is a `PILLAR`, and `Terrain.Feature.blocks_movement()` is
## `WALL or PIT`. Walking into a pillar is legal by design and units do it.
##
## The real defect was that standing inside cover made a unit blind and
## invisible rather than protected. `Tools/StallProbe.gd` found the consequence:
## `floor1_cover` reached the 3600-tick cap once in 2,000 fights, **seed 364**,
## with three units on the same point inside the same pillar and sight BLOCKED
## between them **at distance 0.0**. Nothing could resolve a shot, moving toward
## a target you are standing on covers no ground, and the fight ran forever.
##
## Two levels of test, and both are needed: the geometry, because that is where
## the change is, and the fight, because a predicate returning the right answer
## in isolation is not the claim being made.

const COVER := &"floor1_cover"
const STALL_SEED := 364
const STALL_PARTY := ["geysermancer", "priest", "siege_master", "warrior"]

func _pillar(rect: Rect2) -> Array:
	return [Terrain.make(Terrain.Kind.PILLAR, rect)]

# --- the geometry -----------------------------------------------------------

func test_two_units_inside_the_same_pillar_can_see_each_other() -> void:
	var pillar := _pillar(Rect2(20.0, -250.0, 100.0, 100.0))
	assert_false(Terrain.line_is_blocked(pillar, Vector2(30.0, -172.0), Vector2(80.0, -200.0)),
		"both are standing in it; it is not between them")

## The exact state of seed 364: three units on one point. A degenerate segment
## inside the rect used to read as blocked, which is the worst version of it --
## a unit invisible to something standing on top of it.
func test_a_unit_can_see_another_standing_on_the_same_point() -> void:
	var pillar := _pillar(Rect2(20.0, -250.0, 100.0, 100.0))
	var p := Vector2(30.48582, -172.1138)
	assert_false(Terrain.line_is_blocked(pillar, p, p), "distance zero is never blocked")

## THE LIMIT OF THE RULE, and it is deliberate. A unit inside a pillar is still
## hidden from everyone outside it: cover keeps working, and standing *in* it
## does not become better than standing behind it.
##
## The first version of this change exempted a feature containing *either*
## endpoint, and three tests I did not write went red for it -- a shot that had
## flown into a wall carried on through, and `test_content_rooms.gd` measured the
## colonnade denying far fewer shots. Both endpoints is the case the deadlock is
## made of and nothing more.
func test_a_unit_inside_a_pillar_is_still_hidden_from_outside_it() -> void:
	var pillar := _pillar(Rect2(20.0, -250.0, 100.0, 100.0))
	var inside := Vector2(70.0, -200.0)
	var outside := Vector2(-350.0, -200.0)
	assert_true(Terrain.line_is_blocked(pillar, inside, outside), "looking out of it")
	assert_true(Terrain.line_is_blocked(pillar, outside, inside), "and being looked at, both ways")

## THE NEGATIVE, and it is the one that matters: the change must not stop
## pillars blocking anything. A pillar between two units outside it still does
## its whole job, which is the only reason the colonnade exists.
func test_a_pillar_between_two_units_outside_it_still_blocks() -> void:
	var pillar := _pillar(Rect2(20.0, -250.0, 100.0, 100.0))
	assert_true(Terrain.line_is_blocked(pillar, Vector2(-100.0, -200.0), Vector2(300.0, -200.0)),
		"neither endpoint is inside it, so it is between them and it blocks")

## A WALL never exempts anything, whichever endpoints are inside it. Nothing can
## stand in one -- `blocks_movement()` is true and `_sweep` refuses to land there
## -- so the exemption could only change states the simulation cannot produce,
## and `test_combat_projectiles.gd` guards a real rule through exactly such a
## state: a shot in flight, and a wall dropped over the target.
func test_a_wall_never_stops_blocking_however_it_contains_the_line() -> void:
	var wall := [Terrain.make(Terrain.Kind.WALL, Rect2(0.0, 0.0, 50.0, 50.0))]
	assert_true(Terrain.line_is_blocked(wall, Vector2(25.0, 25.0), Vector2(30.0, 30.0)),
		"both endpoints inside a WALL still blocks; only a feature a unit can stand in is exempt")
	assert_true(Terrain.line_is_blocked(wall, Vector2(25.0, 25.0), Vector2(200.0, 25.0)),
		"one endpoint inside blocks")
	assert_true(Terrain.line_is_blocked(wall, Vector2(-100.0, 25.0), Vector2(200.0, 25.0)),
		"and it still blocks a line that merely crosses it")

# --- the fight --------------------------------------------------------------

## THE REGRESSION. Red before the change, green after, and it is the fight
## rather than the predicate.
func test_the_seed_364_deadlock_resolves() -> void:
	var encounter := Registry.get_encounter(COVER)
	assert_true(encounter != null, "floor1_cover is registered")
	var party: Array[PawnData] = []
	for cid in STALL_PARTY:
		party.append(PawnFactory.make_starter_pawn(
			StringName(cid), StringName("%s_%d" % [cid, party.size()]), String(cid)))
	var state := CombatSim.build(party, encounter, STALL_SEED)
	CombatSim.run(state)

	assert_true(state.tick < CG.MAX_TICKS,
		("seed %d of %s ran to the tick cap again. Three units used to end up on one "
		+ "point inside a pillar, blind to each other at distance zero. If this is red, "
		+ "either that is back or there is a second stall mechanism -- see issue 255.")
			% [STALL_SEED, COVER])
	assert_true(state.outcome != CombatState.Outcome.DRAW,
		"and it reached a real result rather than a draw")
