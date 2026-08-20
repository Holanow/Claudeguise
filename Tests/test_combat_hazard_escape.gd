extends "res://Tests/TestCase.gd"


## Issue 357: `standing_harms` is the rule `_avoid_hazard` steps around, made
## public so a caller outside CombatSim cannot grow a second copy of it.

func test_standing_harms_counts_damage_and_status_but_not_a_decorative_hazard() -> void:
	var damaging := Terrain.hazard(Rect2(0.0, 0.0, 10.0, 10.0), 2, CG.DamageType.FIRE)
	var status_only := Terrain.make(Terrain.Kind.HAZARD, Rect2(20.0, 0.0, 10.0, 10.0))
	status_only.applies_status = CG.Status.SLOWED
	status_only.applies_status_enabled = true
	status_only.status_duration_ticks = 30
	var decorative := Terrain.make(Terrain.Kind.HAZARD, Rect2(40.0, 0.0, 10.0, 10.0))

	var state := CombatState.new(1)
	state.terrain = [damaging, status_only, decorative]

	assert_true(CombatSim.standing_harms(state, Vector2(5.0, 5.0)), "damage per tick harms")
	assert_true(CombatSim.standing_harms(state, Vector2(25.0, 5.0)), "a status with a duration harms even with no damage")
	assert_false(CombatSim.standing_harms(state, Vector2(45.0, 5.0)), "a hazard with neither damage nor a status harms nobody")
	assert_false(CombatSim.standing_harms(state, Vector2(200.0, 200.0)), "clean floor harms nobody")

func test_standing_harms_ignores_walls_and_pillars_that_share_a_rect_with_nothing() -> void:
	var state := CombatState.new(1)
	state.terrain = [
		Terrain.make(Terrain.Kind.WALL, Rect2(0.0, 0.0, 10.0, 10.0)),
		Terrain.make(Terrain.Kind.PIT, Rect2(20.0, 0.0, 10.0, 10.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(40.0, 0.0, 10.0, 10.0)),
	]
	assert_false(CombatSim.standing_harms(state, Vector2(5.0, 5.0)), "a wall is not a hazard")
	assert_false(CombatSim.standing_harms(state, Vector2(25.0, 5.0)), "a pit is not a hazard")
	assert_false(CombatSim.standing_harms(state, Vector2(45.0, 5.0)), "a pillar is not a hazard")
