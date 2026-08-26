extends "res://Tests/TestCase.gd"


## ISSUE 233. A side with nothing left that can act has lost now, not in
## twenty-five seconds.

const _SEED := 23300

func _unit(id: int, team: CG.Team, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = 100
	u.hp = 100
	u.position = pos
	u.move_speed = 0.0
	return u

func _marked_only_action() -> ActionDef:
	var a := ActionDef.new()
	a.id = &"fixture_marked_bolt"
	a.targeting = ActionTargeting.new()
	a.targeting.requires_marked_target = true
	a.targeting.range_units = 9000.0
	var hit := HitEffect.new()
	hit.power_scale = 1.0
	a.effects = [hit] as Array[AbilityEffect]
	return a

func _plain_action() -> ActionDef:
	var a := ActionDef.new()
	a.id = &"fixture_bolt"
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 9000.0
	a.cooldown_ticks = 600
	var hit := HitEffect.new()
	hit.power_scale = 1.0
	a.effects = [hit] as Array[AbilityEffect]
	return a

func _marking_action() -> ActionDef:
	var a := ActionDef.new()
	a.id = &"fixture_mark"
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 9000.0
	var mark := StatusEffect.new()
	mark.status = CG.Status.MARKED
	a.effects = [HitEffect.new(), mark] as Array[AbilityEffect]
	return a

## Idle so nothing in the fixture ever fires. Every outcome below is then the
## outcome rule's doing and nothing else's.
func _deps() -> SimDeps:
	var lookup := {
		&"fixture_marked_bolt": _marked_only_action(),
		&"fixture_bolt": _plain_action(),
		&"fixture_mark": _marking_action(),
	}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName) -> ActionDef: return lookup.get(id, null)
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	deps.plan_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return null
	return deps

## `turret_actions` goes on the one immobile player unit; the enemy is always a
## plain living unit that could keep fighting.
func _state(turret_actions: Array[StringName], enemy_marked: bool, extra_ally: CombatUnit = null) -> CombatState:
	var state := CombatState.new(_SEED)
	var turret := _unit(0, CG.Team.PLAYER, Vector2.ZERO)
	turret.actions = turret_actions
	state.units.append(turret)
	var foe := _unit(1, CG.Team.ENEMY, Vector2(400.0, 0.0))
	foe.actions = [&"fixture_bolt"] as Array[StringName]
	if enemy_marked:
		foe.statuses[CG.Status.MARKED] = 9000
	state.units.append(foe)
	if extra_ally != null:
		extra_ally.id = state.units.size()
		state.units.append(extra_ally)
	return state

func _outcome_after_a_tick(state: CombatState) -> CombatState.Outcome:
	CombatSim.step(state, _deps())
	return state.outcome

# --- the thing itself -------------------------------------------------------

## The measured case: an immobile unit whose only action needs a mark, with
## nothing alive that can apply one.
func test_a_side_of_nothing_but_stranded_turrets_has_lost() -> void:
	var state := _state([&"fixture_marked_bolt"] as Array[StringName], false)
	assert_eq(_outcome_after_a_tick(state), CombatState.Outcome.ENEMY_WIN,
		"an immobile marked-only unit with no mark and no marker left cannot ever act again")
	assert_true(state.unit(0).alive,
		"and it is still alive -- the fight ended because it is spent, not because it died")

# --- the negatives, which are why the rule is safe --------------------------

## Non-vacuity for every case below: the same fixture with the mark present must
## keep running, or the tests underneath prove nothing.
func test_a_live_mark_keeps_the_fight_running() -> void:
	var state := _state([&"fixture_marked_bolt"] as Array[StringName], true)
	assert_eq(_outcome_after_a_tick(state), CombatState.Outcome.UNRESOLVED,
		"the enemy is MARKED, so the turret can still fire")

func test_a_living_ally_that_can_mark_keeps_the_fight_running() -> void:
	var marker := _unit(0, CG.Team.PLAYER, Vector2(-100.0, 0.0))
	marker.actions = [&"fixture_mark"] as Array[StringName]
	var state := _state([&"fixture_marked_bolt"] as Array[StringName], false, marker)
	assert_eq(_outcome_after_a_tick(state), CombatState.Outcome.UNRESOLVED,
		"an ally that applies MARKED can un-strand the turret, so nothing is decided")

## A cooldown is a timer. It resolves itself, so it must never end a fight --
## this is the false positive that would make the rule dangerous.
func test_an_action_merely_on_cooldown_keeps_the_fight_running() -> void:
	var state := _state([&"fixture_bolt"] as Array[StringName], false)
	state.unit(0).cooldowns[&"fixture_bolt"] = 9000
	assert_eq(_outcome_after_a_tick(state), CombatState.Outcome.UNRESOLVED,
		"a cooldown ticks down on its own; a fight may not end because of one")

## So does distance, as long as the unit can walk.
func test_a_unit_that_can_move_keeps_the_fight_running() -> void:
	var state := _state([&"fixture_marked_bolt"] as Array[StringName], false)
	state.unit(0).move_speed = 60.0
	assert_eq(_outcome_after_a_tick(state), CombatState.Outcome.UNRESOLVED,
		"a unit that can move is never stranded by this rule")

## The engines fire a parting shot as the Siege Master dies. Ending the fight
## while it is still in the air would steal a win they earned.
func test_a_shot_still_in_the_air_keeps_the_fight_running() -> void:
	var state := _state([&"fixture_marked_bolt"] as Array[StringName], false)
	var shot := preload("res://Scripts/Core/Projectile.gd").new()
	shot.id = 0
	shot.source_id = 0
	shot.target_id = 1
	shot.action_id = &"fixture_marked_bolt"
	shot.origin = Vector2.ZERO
	shot.aim_point = Vector2(400.0, 0.0)
	shot.position = Vector2(10.0, 0.0)
	shot.speed = 1.0
	shot.spawn_tick = 0
	state.projectiles.append(shot)
	assert_eq(_outcome_after_a_tick(state), CombatState.Outcome.UNRESOLVED,
		"a bolt of the turret's is still resolving; the fight is not over yet")

## The old rule, untouched: an empty side still loses on the same tick.
func test_an_empty_side_still_loses_immediately() -> void:
	var state := _state([&"fixture_marked_bolt"] as Array[StringName], true)
	state.unit(1).alive = false
	assert_eq(_outcome_after_a_tick(state), CombatState.Outcome.PLAYER_WIN,
		"nothing about the ordinary outcome rule changed")
