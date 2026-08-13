extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")

## Issue 14, the simulation half: ActionDef.pull_distance drags a target
## toward the caster on hit, and CG.Status.SLOWED scales move_speed through a
## SimDeps seam. Both are frozen-but-inert shapes until this file; every
## action that exists today has pull_distance == 0.0, which must still behave
## exactly as before.

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

func _dummy_enemy(id: int) -> CombatUnit:
	return _unit(id, CG.Team.ENEMY, 10, Vector2(100000, 100000), [])

func _idle_deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return deps

## wind_up_ticks == 2, matching test_combat_sim.gd's own convention
## (test_a_unit_at_one_hp_still_completes_its_action): the action fires on
## exactly the Nth step() call for a wind-up of N ticks, so every call site
## below steps exactly twice -- once to commit, once to land.
func _hook(id: StringName, pull: float, power: float = 5.0) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 2
	a.recover_ticks = 1
	a.range_units = 999.0
	a.pull_distance = pull
	a.damage_type = CG.DamageType.PHYSICAL
	return a

func _deps_with_action(action: ActionDef, power: float) -> SimDeps:
	var actions_by_id := {action.id: action}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _r = null) -> float: return power
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return deps

# ---------------------------------------------------------------------------
# criterion: a hook drags the target toward the caster
# ---------------------------------------------------------------------------

func test_a_pull_action_drags_the_target_toward_the_caster() -> void:
	var hook := _hook(&"hook", 20.0)
	var deps := _deps_with_action(hook, 5.0)

	var state := CombatState.new(100)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [hook.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(hook.id, target.id)
	CombatSim.step(state, deps) # commits
	CombatSim.step(state, deps) # fires and pulls

	assert_almost_eq(target.position.x, 80.0, 0.01, "pulled 20 units toward the caster")
	assert_almost_eq(target.position.y, 0.0, 0.01)

func test_a_pull_never_drags_the_target_past_the_caster() -> void:
	# pull_distance larger than the actual gap must not overshoot onto or past
	# the caster -- the target lands on top of the caster at most, not beyond.
	var hook := _hook(&"hook", 500.0)
	var deps := _deps_with_action(hook, 5.0)

	var state := CombatState.new(101)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [hook.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(30, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(hook.id, target.id)
	CombatSim.step(state, deps)
	CombatSim.step(state, deps)

	assert_almost_eq(target.position.x, 0.0, 0.01, "must land exactly at the caster, not past it")

func test_zero_pull_distance_leaves_the_target_exactly_where_it_was() -> void:
	# Every action that exists today has pull_distance == 0.0. This is the
	# "changes no behaviour" half of the frozen shape.
	var atk := _hook(&"atk", 0.0)
	var deps := _deps_with_action(atk, 5.0)

	var state := CombatState.new(102)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(30, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps)
	CombatSim.step(state, deps)

	assert_eq(target.position, Vector2(30, 0), "pull_distance 0.0 must not move the target at all")

# ---------------------------------------------------------------------------
# criterion: a pull never places a unit inside terrain
# ---------------------------------------------------------------------------

func test_a_pull_stops_at_a_wall_instead_of_passing_through_it() -> void:
	var hook := _hook(&"hook", 200.0)
	var deps := _deps_with_action(hook, 5.0)

	var state := CombatState.new(103)
	var wall := Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(20, -100), Vector2(20, 200)))
	state.terrain.append(wall)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [hook.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(hook.id, target.id)
	CombatSim.step(state, deps)
	CombatSim.step(state, deps)

	assert_true(target.position.x >= wall.rect.position.x + wall.rect.size.x,
		"a pulled target must not be dragged through a wall; landed at %s" % target.position)

# ---------------------------------------------------------------------------
# criterion: a pull never fires after the target is dead
# ---------------------------------------------------------------------------

func test_a_killing_blow_does_not_also_drag_the_corpse() -> void:
	var hook := _hook(&"hook", 50.0)
	var deps := _deps_with_action(hook, 100.0) # heavily overkill, one-shots

	var state := CombatState.new(104)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [hook.id])
	var target := _unit(1, CG.Team.ENEMY, 10, Vector2(100, 0), [])
	state.units.append(caster)
	state.units.append(target)

	caster.intent = Intent.use_action(hook.id, target.id)
	CombatSim.step(state, deps)
	CombatSim.step(state, deps)

	assert_false(target.alive, "sanity: the overkill hit must have killed it")
	assert_eq(target.position, Vector2(100, 0), "a killing blow must not also drag the corpse")

# ---------------------------------------------------------------------------
# criterion: SLOWED scales move_speed through the SimDeps seam
# ---------------------------------------------------------------------------

func test_slowed_status_reduces_effective_move_speed() -> void:
	var deps := _idle_deps()
	deps.slowed_speed_scale = func(_u: CombatUnit) -> float: return 0.5

	var state := CombatState.new(105)
	var unit := _unit(0, CG.Team.PLAYER, 10, Vector2.ZERO, [])
	unit.move_speed = 10.0
	unit.statuses[CG.Status.SLOWED] = 999
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	unit.intent = Intent.move_to(Vector2(1000, 0))
	CombatSim.step(state, deps)

	assert_almost_eq(unit.position.x, 5.0, 0.01, "SLOWED at scale 0.5 must halve the tick's movement")

func test_an_unslowed_unit_is_unaffected_by_the_scale_seam() -> void:
	var deps := _idle_deps()
	deps.slowed_speed_scale = func(_u: CombatUnit) -> float: return 0.1 # would be obvious if wrongly applied

	var state := CombatState.new(106)
	var unit := _unit(0, CG.Team.PLAYER, 10, Vector2.ZERO, [])
	unit.move_speed = 10.0
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	unit.intent = Intent.move_to(Vector2(1000, 0))
	CombatSim.step(state, deps)

	assert_almost_eq(unit.position.x, 10.0, 0.01, "a unit without SLOWED must move at full move_speed")

func test_slow_expires_and_speed_returns_to_normal() -> void:
	var deps := _idle_deps()
	deps.slowed_speed_scale = func(_u: CombatUnit) -> float: return 0.0 # fully rooted while slowed, for a sharp before/after

	var state := CombatState.new(107)
	var unit := _unit(0, CG.Team.PLAYER, 10, Vector2.ZERO, [])
	unit.move_speed = 10.0
	unit.statuses[CG.Status.SLOWED] = 2 # expires once state.tick >= 2
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	unit.intent = Intent.move_to(Vector2(1000, 0))
	CombatSim.step(state, deps) # tick 1: slowed, rooted
	assert_almost_eq(unit.position.x, 0.0, 0.01, "fully slowed must not move at all")

	unit.intent = Intent.move_to(Vector2(1000, 0))
	CombatSim.step(state, deps) # tick 2: still slowed for this tick's move
	assert_false(unit.has_status(CG.Status.SLOWED), "SLOWED must actually be gone once expired")

	unit.intent = Intent.move_to(Vector2(1000, 0))
	CombatSim.step(state, deps) # tick 3: back to full speed
	assert_almost_eq(unit.position.x, 10.0, 0.01, "speed must return to normal once SLOWED expires")

# ---------------------------------------------------------------------------
# criterion: determinism survives with pull and slow both in play
# ---------------------------------------------------------------------------

func test_determinism_holds_with_pull_and_slow_in_play() -> void:
	var hook := _hook(&"hook", 30.0)

	var make_deps := func() -> SimDeps:
		var d := _deps_with_action(hook, 6.0)
		d.slowed_speed_scale = func(_u: CombatUnit) -> float: return 0.4
		return d

	var make_state := func(seed: int) -> CombatState:
		var s := CombatState.new(seed)
		var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [hook.id])
		var target := _unit(1, CG.Team.ENEMY, 30, Vector2(150, 0), [])
		target.statuses[CG.Status.SLOWED] = 999
		s.units.append(caster)
		s.units.append(target)
		caster.intent = Intent.use_action(hook.id, target.id)
		return s

	var state_a: CombatState = make_state.call(555)
	var state_b: CombatState = make_state.call(555)
	var deps_a: SimDeps = make_deps.call()
	var deps_b: SimDeps = make_deps.call()

	for i in 10:
		CombatSim.step(state_a, deps_a)
		CombatSim.step(state_b, deps_b)

	assert_eq(state_a.units[1].position, state_b.units[1].position, "same seed, same pull, same landing position")
	assert_eq(state_a.events.size(), state_b.events.size(), "same seed, same event count")
	for i in state_a.events.size():
		var ea: CombatEvent = state_a.events[i]
		var eb: CombatEvent = state_b.events[i]
		assert_eq(ea.kind, eb.kind, "event %d kind diverged" % i)
		assert_eq(ea.amount, eb.amount, "event %d amount diverged" % i)
