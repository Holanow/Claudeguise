extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const DefaultBehavior := preload("res://Scripts/Plans/DefaultBehavior.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")

## DefaultBehavior tested two ways: direct decide() calls for the precise,
## single-decision cases (heals fire only when needed), and a real
## CombatSim.step loop with a hand-built two-unit CombatState for the range
## behaviour, which needs many ticks of movement to become a "median distance"
## rather than a single decision. CombatSim is real now that issue 1 has
## landed; either way the state and its units are hand-built, per issue 2's
## note not to depend on Registry's encounter or on CombatSim.build.

func _unit(id: int, team: CG.Team, enemy_id: StringName, pos: Vector2) -> CombatUnit:
	var def := Registry.get_enemy(enemy_id)
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.enemy_id = enemy_id
	u.position = pos
	u.hp_max = 1000000
	u.hp = u.hp_max
	u.resource_max = def.resource_max
	u.resource_kind = def.resource_kind
	u.move_speed = def.move_speed
	u.radius = def.radius
	u.actions = def.actions.duplicate()
	return u

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

func _median_distance_over_fight(attacker_id: StringName, ticks: int) -> float:
	var state := CombatState.new(1)
	var attacker := _unit(0, CG.Team.PLAYER, attacker_id, Vector2(-400.0, 0.0))
	var dummy := _immobile_dummy(1, CG.Team.ENEMY, Vector2.ZERO)
	state.units.append(attacker)
	state.units.append(dummy)

	var distances: Array[float] = []
	for i in ticks:
		CombatSim.step(state)
		distances.append(attacker.position.distance_to(dummy.position))
	distances.sort()
	return distances[distances.size() / 2]


func test_ranged_default_behaviour_keeps_more_distance_than_melee() -> void:
	# Measured over 300 ticks (10 seconds) against a stationary target.
	var ranged_median := _median_distance_over_fight(&"goblin_archer", 300)
	var melee_median := _median_distance_over_fight(&"goblin", 300)
	print("DefaultBehavior range check: ranged median=%.1f melee median=%.1f" % [ranged_median, melee_median])
	assert_true(ranged_median > melee_median * 1.5, "ranged (%.1f) should sit well further back than melee (%.1f)" % [ranged_median, melee_median])


func test_healer_heals_hurt_ally() -> void:
	var priest_pawn := PawnFactory.make_starter_pawn(&"priest", &"p1", "Priest")
	var priest := CombatUnit.new()
	priest.id = 0
	priest.team = CG.Team.PLAYER
	priest.pawn = priest_pawn
	priest.position = Vector2.ZERO
	priest.hp_max = 100
	priest.hp = 100
	priest.actions = priest_pawn.pawn_class.starting_actions.duplicate()

	var hurt_ally := CombatUnit.new()
	hurt_ally.id = 1
	hurt_ally.team = CG.Team.PLAYER
	hurt_ally.position = Vector2(50.0, 0.0)
	hurt_ally.hp_max = 100
	hurt_ally.hp = 30

	var enemy := CombatUnit.new()
	enemy.id = 2
	enemy.team = CG.Team.ENEMY
	enemy.position = Vector2(100.0, 0.0)
	enemy.hp_max = 50
	enemy.hp = 50

	var state := CombatState.new(0)
	state.units.append(priest)
	state.units.append(hurt_ally)
	state.units.append(enemy)

	var intent := DefaultBehavior.decide(state, priest)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	var action := Registry.get_action(intent.action_id)
	assert_true(action.heals, "should pick the heal action when an ally is below half hp")
	assert_eq(intent.target_id, hurt_ally.id)


func test_healer_does_not_heal_full_health_allies() -> void:
	var priest_pawn := PawnFactory.make_starter_pawn(&"priest", &"p1", "Priest")
	var priest := CombatUnit.new()
	priest.id = 0
	priest.team = CG.Team.PLAYER
	priest.pawn = priest_pawn
	priest.position = Vector2.ZERO
	priest.hp_max = 100
	priest.hp = 100
	priest.actions = priest_pawn.pawn_class.starting_actions.duplicate()

	var healthy_ally := CombatUnit.new()
	healthy_ally.id = 1
	healthy_ally.team = CG.Team.PLAYER
	healthy_ally.position = Vector2(50.0, 0.0)
	healthy_ally.hp_max = 100
	healthy_ally.hp = 100

	var enemy := CombatUnit.new()
	enemy.id = 2
	enemy.team = CG.Team.ENEMY
	enemy.position = Vector2(100.0, 0.0)
	enemy.hp_max = 50
	enemy.hp = 50

	var state := CombatState.new(0)
	state.units.append(priest)
	state.units.append(healthy_ally)
	state.units.append(enemy)

	var intent := DefaultBehavior.decide(state, priest)
	if intent.kind == CG.IntentKind.USE_ACTION:
		var action := Registry.get_action(intent.action_id)
		assert_false(action.heals, "should not spend a turn healing when nobody needs it")
	else:
		assert_eq(intent.kind, CG.IntentKind.MOVE_TO, "should still do something useful, like closing to attack range")


func test_no_living_enemies_means_idle() -> void:
	var priest_pawn := PawnFactory.make_starter_pawn(&"priest", &"p1", "Priest")
	var priest := CombatUnit.new()
	priest.id = 0
	priest.team = CG.Team.PLAYER
	priest.pawn = priest_pawn
	priest.actions = priest_pawn.pawn_class.starting_actions.duplicate()

	var state := CombatState.new(0)
	state.units.append(priest)

	var intent := DefaultBehavior.decide(state, priest)
	assert_eq(intent.kind, CG.IntentKind.IDLE)
