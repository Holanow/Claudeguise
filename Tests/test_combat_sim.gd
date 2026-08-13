extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")

## Every test here builds CombatUnits and ActionDefs by hand and sets intents
## by hand, per issue 1: Balance and PlanInterpreter are teal's stubs and this
## file must not wait for them. `_deps()` and `_make_attack_nearest()` are the
## whole test-only "content system": fixed numbers and one simple decision
## rule, wired through SimDeps rather than Registry or Balance.

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _melee(id: StringName, wind_up: int, recover: int, range_units: float, power_scale: float = 1.0) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = wind_up
	a.recover_ticks = recover
	a.range_units = range_units
	a.power_scale = power_scale
	a.damage_type = CG.DamageType.PHYSICAL
	return a

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2, actions: Array[StringName]) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.position = pos
	u.move_speed = 8.0
	u.actions = actions
	return u

## Fixed-number SimDeps: every action costs `power` times its power_scale, no
## mitigation, no tick scaling. "Whatever numbers make the case clear."
func _deps(actions_by_id: Dictionary, power: float) -> SimDeps:
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u: CombatUnit, a: ActionDef) -> float: return power * a.power_scale
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	# Every hand-built unit is idle by default (no plans, no DefaultBehavior
	# stub calls). Tests that need real decisions override this explicitly.
	deps.default_decide = func(_state: CombatState, _unit: CombatUnit) -> Intent: return Intent.idle()
	return deps

## The only "AI" in this file: close to range, then attack the nearest living
## enemy with the unit's first action. Good enough to drive a whole fight
## through CombatSim.run without PlanInterpreter or DefaultBehavior existing.
func _make_attack_nearest(actions_by_id: Dictionary) -> Callable:
	return func(state: CombatState, unit: CombatUnit) -> Intent:
		var enemy_team := CG.Team.ENEMY if unit.team == CG.Team.PLAYER else CG.Team.PLAYER
		var enemies := state.living(enemy_team)
		if enemies.is_empty() or unit.actions.is_empty():
			return Intent.idle()
		var target: CombatUnit = enemies[0]
		for e in enemies:
			if unit.position.distance_to(e.position) < unit.position.distance_to(target.position):
				target = e
		var action: ActionDef = actions_by_id[unit.actions[0]]
		if unit.position.distance_to(target.position) > action.range_units:
			return Intent.move_to(target.position)
		return Intent.use_action(action.id, target.id)

# ---------------------------------------------------------------------------
# build()
# ---------------------------------------------------------------------------

func test_build_places_party_and_enemies_and_emits_fight_start() -> void:
	var cls := ClassDef.new()
	cls.id = &"tester"
	cls.resource_kind = CG.ResourceKind.ENERGY

	var pawn := PawnData.new()
	pawn.id = &"p1"
	pawn.display_name = "Test Pawn"
	pawn.pawn_class = cls

	var enemy_def := EnemyDef.new()
	enemy_def.id = &"grub"
	enemy_def.display_name = "Grub"
	enemy_def.hp_max = 8
	enemy_def.move_speed = 2.0

	var encounter := Encounter.new()
	encounter.party_spawns = [Vector2(-50, 0)]
	encounter.enemy_spawns = [{"enemy_id": &"grub", "position": Vector2(50, 0)}]

	var deps := SimDeps.new()
	deps.max_hp = func(_p: PawnData) -> int: return 25
	deps.max_resource = func(_p: PawnData) -> int: return 10
	deps.move_speed = func(_p: PawnData) -> float: return 4.0
	deps.enemy_lookup = func(id: StringName): return enemy_def if id == &"grub" else null

	var state := CombatSim.build([pawn], encounter, 42, deps)

	assert_eq(state.units.size(), 2)

	var player_unit := state.unit(0)
	assert_eq(player_unit.team, CG.Team.PLAYER)
	assert_eq(player_unit.hp, 25)
	assert_eq(player_unit.hp_max, 25)
	assert_eq(player_unit.position, Vector2(-50, 0))

	var enemy_unit := state.unit(1)
	assert_eq(enemy_unit.team, CG.Team.ENEMY)
	assert_eq(enemy_unit.hp, 8)
	assert_eq(enemy_unit.position, Vector2(50, 0))

	assert_eq(state.events.size(), 1)
	assert_eq(state.events[0].kind, CG.EventKind.FIGHT_START)

# ---------------------------------------------------------------------------
# criterion 1: a fight resolves both ways
# ---------------------------------------------------------------------------

func test_a_party_that_outclasses_the_enemies_wins() -> void:
	var atk := _melee(&"atk", 1, 1, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 10.0)
	deps.default_decide = _make_attack_nearest(actions_by_id)

	var state := CombatState.new(1)
	state.units.append(_unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id]))
	state.units.append(_unit(1, CG.Team.PLAYER, 30, Vector2(10, 0), [atk.id]))
	state.units.append(_unit(2, CG.Team.ENEMY, 5, Vector2(20, 0), []))
	state.units.append(_unit(3, CG.Team.ENEMY, 5, Vector2(30, 0), []))

	var outcome := CombatSim.run(state, deps)

	assert_eq(outcome, CombatState.Outcome.PLAYER_WIN)
	assert_eq(state.outcome, CombatState.Outcome.PLAYER_WIN)
	# A fight that can resolve does so well before MAX_TICKS: the cap must not
	# be quietly deciding this one.
	assert_true(state.tick < CG.MAX_TICKS / 10, "a trivial win took %d ticks" % state.tick)

func test_an_enemy_group_that_outclasses_the_party_wins() -> void:
	var atk := _melee(&"atk", 1, 1, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 10.0)
	deps.default_decide = _make_attack_nearest(actions_by_id)

	var state := CombatState.new(2)
	state.units.append(_unit(0, CG.Team.PLAYER, 5, Vector2.ZERO, []))
	state.units.append(_unit(1, CG.Team.ENEMY, 30, Vector2(10, 0), [atk.id]))
	state.units.append(_unit(2, CG.Team.ENEMY, 30, Vector2(20, 0), [atk.id]))

	var outcome := CombatSim.run(state, deps)

	assert_eq(outcome, CombatState.Outcome.ENEMY_WIN)
	assert_true(state.tick < CG.MAX_TICKS / 10, "a trivial loss took %d ticks" % state.tick)

# ---------------------------------------------------------------------------
# criterion 2: a stalemate ends
# ---------------------------------------------------------------------------

func test_two_units_that_cannot_reach_each_other_draw_at_max_ticks() -> void:
	var deps := SimDeps.new()
	deps.default_decide = func(_state: CombatState, _unit: CombatUnit) -> Intent: return Intent.idle()

	var state := CombatState.new(3)
	state.units.append(_unit(0, CG.Team.PLAYER, 10, Vector2.ZERO, []))
	state.units.append(_unit(1, CG.Team.ENEMY, 10, Vector2(1000000, 0), []))

	var outcome := CombatSim.run(state, deps)

	assert_eq(outcome, CombatState.Outcome.DRAW)
	assert_eq(state.tick, CG.MAX_TICKS)

# ---------------------------------------------------------------------------
# criterion 3: the same seed gives the same fight
# ---------------------------------------------------------------------------

func _outclass_state(seed: int, atk_id: StringName) -> CombatState:
	var state := CombatState.new(seed)
	state.units.append(_unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk_id]))
	state.units.append(_unit(1, CG.Team.PLAYER, 30, Vector2(10, 0), [atk_id]))
	state.units.append(_unit(2, CG.Team.ENEMY, 5, Vector2(20, 0), []))
	state.units.append(_unit(3, CG.Team.ENEMY, 5, Vector2(30, 0), []))
	return state

func _assert_same_events(a: CombatState, b: CombatState, message: String) -> void:
	assert_eq(a.events.size(), b.events.size(), "%s: event count diverged" % message)
	for i in mini(a.events.size(), b.events.size()):
		var ea: CombatEvent = a.events[i]
		var eb: CombatEvent = b.events[i]
		assert_eq(ea.kind, eb.kind, "%s: event %d kind diverged" % [message, i])
		assert_eq(ea.tick, eb.tick, "%s: event %d tick diverged" % [message, i])
		assert_eq(ea.amount, eb.amount, "%s: event %d amount diverged" % [message, i])
		assert_eq(ea.source_id, eb.source_id, "%s: event %d source diverged" % [message, i])
		assert_eq(ea.target_id, eb.target_id, "%s: event %d target diverged" % [message, i])

func test_same_seed_gives_identical_event_list() -> void:
	var atk := _melee(&"atk", 1, 1, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 7.0)
	deps.default_decide = _make_attack_nearest(actions_by_id)

	var a := _outclass_state(12345, atk.id)
	var b := _outclass_state(12345, atk.id)
	CombatSim.run(a, deps)
	CombatSim.run(b, deps)

	_assert_same_events(a, b, "same seed")

func test_different_seeds_still_agree_because_rng_is_not_consulted() -> void:
	# Criterion 3's own escape clause: "two different seeds produce different
	# [fights], or the rng is not being consulted at all." This slice has no
	# crit rolls or variance, so CombatSim never touches state.rng. The test
	# that proves it: two different seeds, identical inputs otherwise, must
	# still produce the identical fight.
	var atk := _melee(&"atk", 1, 1, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 7.0)
	deps.default_decide = _make_attack_nearest(actions_by_id)

	var a := _outclass_state(1, atk.id)
	var b := _outclass_state(2, atk.id)
	CombatSim.run(a, deps)
	CombatSim.run(b, deps)

	_assert_same_events(a, b, "different seeds, rng unused")

# ---------------------------------------------------------------------------
# criterion 4: range is measured when the effect lands
# ---------------------------------------------------------------------------

func test_target_that_leaves_range_during_windup_is_missed() -> void:
	var atk := _melee(&"atk", 3, 1, 15.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 10.0)

	var state := CombatState.new(9)
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(10, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps) # commits: in range at commit time

	target.position = Vector2(100000, 0) # walks out of range during the wind-up

	CombatSim.step(state, deps)
	CombatSim.step(state, deps) # wind-up completes here

	var fired := false
	var damaged := false
	for e in state.events:
		if e.kind == CG.EventKind.ACTION_FIRE and e.source_id == 0:
			fired = true
		if e.kind == CG.EventKind.DAMAGE and e.source_id == 0:
			damaged = true

	assert_true(fired, "the attempt is still logged even on a miss")
	assert_false(damaged, "a target that left range must not take damage")
	assert_eq(target.hp, target.hp_max)

func test_target_that_stays_in_range_is_hit() -> void:
	var atk := _melee(&"atk", 3, 1, 15.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 10.0)

	var state := CombatState.new(9)
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(10, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	for i in 3:
		CombatSim.step(state, deps)

	assert_eq(target.hp, target.hp_max - 10)

# ---------------------------------------------------------------------------
# criterion 5: death stops everything
# ---------------------------------------------------------------------------

func test_a_unit_that_dies_mid_windup_does_not_land_its_action() -> void:
	var slow := _melee(&"slow", 5, 1, 999.0)
	var quick := _melee(&"quick", 1, 1, 999.0)
	var actions_by_id := {slow.id: slow, quick.id: quick}
	var deps := _deps(actions_by_id, 100.0) # heavily overkill, one-shots

	var state := CombatState.new(4)
	var victim := _unit(0, CG.Team.PLAYER, 10, Vector2.ZERO, [slow.id])
	var killer := _unit(1, CG.Team.ENEMY, 10, Vector2(5, 0), [quick.id])
	state.units.append(victim)
	state.units.append(killer)

	victim.intent = Intent.use_action(slow.id, killer.id) # 5-tick wind-up
	CombatSim.step(state, deps) # tick 1: victim commits

	killer.intent = Intent.use_action(quick.id, victim.id) # 1-tick wind-up
	CombatSim.step(state, deps) # tick 2: killer commits and fires this same tick

	assert_false(victim.alive)

	# Run past the point victim's original 5-tick wind-up would have landed.
	for i in 4:
		CombatSim.step(state, deps)

	for e in state.events:
		assert_false(
			e.kind == CG.EventKind.ACTION_FIRE and e.source_id == 0,
			"a dead unit's action must not fire"
		)
		assert_false(
			e.kind == CG.EventKind.DAMAGE and e.source_id == 0,
			"a dead unit must not land damage"
		)

func test_a_unit_at_one_hp_still_completes_its_action() -> void:
	var atk := _melee(&"atk", 2, 1, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 5.0)

	var state := CombatState.new(5)
	var attacker := _unit(0, CG.Team.PLAYER, 1, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(5, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	for i in 2:
		CombatSim.step(state, deps)

	assert_true(attacker.alive)
	assert_eq(target.hp, target.hp_max - 5)

	var fired := false
	for e in state.events:
		if e.kind == CG.EventKind.ACTION_FIRE and e.source_id == 0:
			fired = true
	assert_true(fired, "a unit at 1 hp must still land its committed action")

# ---------------------------------------------------------------------------
# criterion 6: every state change has an event
# ---------------------------------------------------------------------------

func test_replaying_damage_events_reaches_the_same_hp() -> void:
	var atk := _melee(&"atk", 1, 1, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 6.0)
	deps.default_decide = _make_attack_nearest(actions_by_id)

	var state := CombatState.new(6)
	state.units.append(_unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [atk.id]))
	state.units.append(_unit(1, CG.Team.ENEMY, 13, Vector2(1, 0), [atk.id]))

	var start_hp := {0: 20, 1: 13}
	CombatSim.run(state, deps)

	var replayed := start_hp.duplicate()
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE:
			replayed[e.target_id] = replayed[e.target_id] - e.amount
		elif e.kind == CG.EventKind.HEAL:
			replayed[e.target_id] = replayed[e.target_id] + e.amount

	for u in state.units:
		assert_eq(replayed[u.id], u.hp, "unit %d hp diverges from its event replay" % u.id)
