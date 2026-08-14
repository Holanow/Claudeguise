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


## TAUNTING, in DefaultBehavior._choose_target (via _nearest_taunter). Real
## decide() calls throughout, not the private helper directly, matching how
## every other test in this file exercises DefaultBehavior -- through its
## one public entry point.
##
## goblin_archer's own kit (range 200, requires_line_of_sight) is used for
## all four, positioned so the ranged commit window (dist in
## [kite_min, commit_max] = [120, 170] for this action) is unambiguous:
## a hit lands as USE_ACTION with a real target_id, not a MOVE_TO whose
## destination has to be compared instead.

func _taunter(id: int, pos: Vector2, radius: float) -> CombatUnit:
	var u := _immobile_dummy(id, CG.Team.ENEMY, pos)
	u.statuses[CG.Status.TAUNTING] = 999999
	u.taunt_radius = radius
	return u

func test_taunt_overrides_the_nearest_enemy() -> void:
	var state := CombatState.new(1)
	var attacker := _unit(0, CG.Team.PLAYER, &"goblin_archer", Vector2.ZERO)
	var nearest := _immobile_dummy(1, CG.Team.ENEMY, Vector2(50.0, 0.0))
	var taunter := _taunter(2, Vector2(150.0, 0.0), 999.0)
	state.units.append(attacker)
	state.units.append(nearest)
	state.units.append(taunter)

	var intent := DefaultBehavior.decide(state, attacker)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION, "expected a committed attack, not a move")
	assert_eq(intent.target_id, taunter.id, "a taunting enemy in range should be targeted over a nearer non-taunting one")


func test_taunt_out_of_its_own_radius_does_not_override() -> void:
	var state := CombatState.new(1)
	var attacker := _unit(0, CG.Team.PLAYER, &"goblin_archer", Vector2.ZERO)
	# Beyond the ranged commit window (170), so the baseline behaviour is
	# closing distance on it -- unambiguous MOVE_TO(nearest.position).
	var nearest := _immobile_dummy(1, CG.Team.ENEMY, Vector2(180.0, 0.0))
	# Taunting, but taunt_radius does not reach the attacker's position.
	var taunter := _taunter(2, Vector2(300.0, 0.0), 10.0)
	state.units.append(attacker)
	state.units.append(nearest)
	state.units.append(taunter)

	var intent := DefaultBehavior.decide(state, attacker)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO, "the nearest enemy is out of ranged commit range, so this should still be closing distance on it")
	# MOVE_TO carries no target_id; destination is the nearest enemy's own position.
	assert_eq(intent.destination, nearest.position)


func test_an_untaunting_enemy_is_never_treated_as_a_taunter() -> void:
	var state := CombatState.new(1)
	var attacker := _unit(0, CG.Team.PLAYER, &"goblin_archer", Vector2.ZERO)
	var nearest := _immobile_dummy(1, CG.Team.ENEMY, Vector2(150.0, 0.0))
	state.units.append(attacker)
	state.units.append(nearest)

	var intent := DefaultBehavior.decide(state, attacker)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.target_id, nearest.id, "with nobody taunting, ordinary nearest-target selection should be untouched")


func test_taunt_works_symmetrically_for_an_enemy_unit_too() -> void:
	# The Warrior taunting real enemies is the primary case per the class
	# fantasy -- TAUNTING and _nearest_taunter are generic over team, same
	## as _choose_target already is, so this checks the enemy side directly
	## rather than assuming symmetry.
	var state := CombatState.new(1)
	var attacker := _unit(0, CG.Team.ENEMY, &"goblin_archer", Vector2.ZERO)
	var nearest := _immobile_dummy(1, CG.Team.PLAYER, Vector2(50.0, 0.0))
	var taunter := _taunter(2, Vector2(150.0, 0.0), 999.0)
	taunter.team = CG.Team.PLAYER
	state.units.append(attacker)
	state.units.append(nearest)
	state.units.append(taunter)

	var intent := DefaultBehavior.decide(state, attacker)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.target_id, taunter.id)


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


## PLAYTEST-NOTES-2.md note 11: "The Abomination runs away a lot... tanks
## should move toward enemies." Root cause traced directly: `abomination_hook`
## (range 140) is classified "ranged" by `MELEE_RANGE_THRESHOLD`, so it
## inherited the standard kite-and-retreat behaviour built for a stay-at-
## range weapon -- exactly wrong for a pull, whose entire point is closing
## distance. 60 units away is inside hook's own 84-unit kite band (0.6 * 140)
## and outside grapple's own melee commit range (22.5), so the old retreat
## branch is exactly what would fire here; `resource` is drained on purpose
## to rule out a plan (both `abomination_grapple_close`/`abomination_hook_far`
## would be unaffordable) -- this exercises DefaultBehavior's fallback
## directly, the same thing PlanInterpreter falls through to mid-fight once
## Rage runs low.
func test_a_pull_action_never_retreats_even_inside_its_own_kite_band() -> void:
	var abom_pawn := PawnFactory.make_starter_pawn(&"abomination", &"a1", "Abomination")
	var abom := CombatUnit.new()
	abom.id = 0
	abom.team = CG.Team.PLAYER
	abom.pawn = abom_pawn
	abom.position = Vector2.ZERO
	abom.hp_max = 200
	abom.hp = 200
	abom.resource_kind = CG.ResourceKind.RAGE
	abom.resource_max = 100
	abom.resource = 0
	abom.actions = abom_pawn.pawn_class.starting_actions.duplicate()

	var enemy := _immobile_dummy(1, CG.Team.ENEMY, Vector2(60.0, 0.0))
	var state := CombatState.new(0)
	state.units.append(abom)
	state.units.append(enemy)

	var intent := DefaultBehavior.decide(state, abom)
	if intent.kind == CG.IntentKind.MOVE_TO:
		var old_dist := abom.position.distance_to(enemy.position)
		var new_dist := intent.destination.distance_to(enemy.position)
		assert_true(new_dist <= old_dist, "a pull action must never order a retreat, got a move to %s (was %.1f away, would end %.1f away)" % [intent.destination, old_dist, new_dist])
	else:
		assert_eq(intent.kind, CG.IntentKind.USE_ACTION, "expected either an approach or a committed cast, not idle")
		assert_eq(intent.target_id, enemy.id)


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
