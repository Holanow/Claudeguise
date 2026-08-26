extends "res://Tests/TestCase.gd"


## Issue 28a: line of sight is measured the same place and the same moment as
## range -- at the moment the effect lands, against ActionDef.requires_line_of_sight
## and TerrainGrid.sight_blocked. Same helper shapes as test_combat_sim.gd and
## test_combat_terrain.gd; not shared via preload since GDScript test files
## don't share state.

func _sighted(id: StringName, wind_up: int, recover: int, range_units: float) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = wind_up
	a.recover_ticks = recover
	a.range_units = range_units
	a.damage_type = CG.DamageType.PHYSICAL
	a.requires_line_of_sight = true
	return a

func _unsighted(id: StringName, wind_up: int, recover: int, range_units: float) -> ActionDef:
	var a := _sighted(id, wind_up, recover, range_units)
	a.requires_line_of_sight = false
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

func _deps(actions_by_id: Dictionary, power: float) -> SimDeps:
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u: CombatUnit, a: ActionDef, _rng = null) -> float: return power
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_state: CombatState, _unit: CombatUnit) -> Intent: return Intent.idle()
	return deps

## A wall between attacker (x=0) and target (x=10): thin, and short enough
## (y -10..10) that a target well clear of that band (y=200) has an
## unambiguously open line, while y=0 is unambiguously blocked. Full-height
## would leave every plausible "clear" y still crossing the wall's x-band.
func _wall() -> Terrain.Feature:
	return Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(4, -10), Vector2(2, 20)))

# ---------------------------------------------------------------------------
# criterion 1: a wall blocks a sighted action; no wall lets it land
# ---------------------------------------------------------------------------

func test_a_wall_blocks_a_line_of_sight_action() -> void:
	var atk := _sighted(&"atk", 3, 1, 15.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 10.0)

	var state := CombatState.new(1)
	state.grid.stamp_features([_wall()])
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(10, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	for i in 3:
		CombatSim.step(state, deps)

	assert_eq(target.hp, target.hp_max, "a wall between attacker and target must block a sighted action")
	var miss_count := 0
	for e in state.events:
		if e.kind == CG.EventKind.MISS and e.source_id == 0:
			miss_count += 1
	assert_eq(miss_count, 1, "a blocked shot is a MISS")

func test_no_wall_lets_a_line_of_sight_action_land() -> void:
	var atk := _sighted(&"atk", 3, 1, 15.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 10.0)

	var state := CombatState.new(2)
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(10, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	for i in 3:
		CombatSim.step(state, deps)

	assert_eq(target.hp, target.hp_max - 10, "with no wall, a sighted action lands normally")

# ---------------------------------------------------------------------------
# criterion 2: cover during the wind-up is the case terrain exists for
# ---------------------------------------------------------------------------

func test_a_target_that_steps_behind_cover_during_the_windup_is_missed() -> void:
	# Range widened to 150 for this pair of tests: the "clear" position has to
	# sit far enough in y that its line to the attacker unambiguously misses
	# the wall's x-band, which puts it well outside a 15-unit range.
	var atk := _sighted(&"atk", 3, 1, 150.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 10.0)

	var state := CombatState.new(3)
	state.grid.stamp_features([_wall()])
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(10, 100), []) # clear of the wall at commit
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps) # commits: clear line of sight at commit time

	target.position = Vector2(10, 0) # steps behind the wall during the wind-up

	CombatSim.step(state, deps)
	CombatSim.step(state, deps) # wind-up completes here

	assert_eq(target.hp, target.hp_max, "a target that steps behind cover during the wind-up must be missed")
	var miss_count := 0
	for e in state.events:
		if e.kind == CG.EventKind.MISS and e.source_id == 0:
			miss_count += 1
	assert_eq(miss_count, 1)

func test_a_target_that_steps_out_from_behind_cover_during_the_windup_is_hit() -> void:
	var atk := _sighted(&"atk", 3, 1, 150.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 10.0)

	var state := CombatState.new(4)
	state.grid.stamp_features([_wall()])
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(10, 0), []) # behind the wall at commit
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps) # commits: blocked at commit time, but range/sight are re-measured on landing, not at commit

	target.position = Vector2(10, 100) # steps clear of the wall during the wind-up

	CombatSim.step(state, deps)
	CombatSim.step(state, deps) # wind-up completes here

	assert_eq(target.hp, target.hp_max - 10, "a target that steps out from behind cover during the wind-up must be hit")

# ---------------------------------------------------------------------------
# criterion 3: an action without the flag is unaffected by any wall
# ---------------------------------------------------------------------------

func test_an_action_without_the_flag_fires_straight_through_a_wall() -> void:
	var atk := _unsighted(&"atk", 3, 1, 15.0)
	var actions_by_id := {atk.id: atk}
	var deps := _deps(actions_by_id, 10.0)

	var state := CombatState.new(5)
	state.grid.stamp_features([_wall()])
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(10, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	for i in 3:
		CombatSim.step(state, deps)

	assert_eq(target.hp, target.hp_max - 10, "nothing that works today changes until an action opts in")

# ---------------------------------------------------------------------------
# criterion 4: determinism survives
# ---------------------------------------------------------------------------

func test_determinism_holds_with_line_of_sight_in_play() -> void:
	var atk := _sighted(&"atk", 3, 1, 15.0)
	var actions_by_id := {atk.id: atk}

	var make_state := func(seed: int) -> CombatState:
		var s := CombatState.new(seed)
		s.grid.stamp_features([_wall()])
		var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
		var target := _unit(1, CG.Team.ENEMY, 30, Vector2(10, 0), [])
		s.units.append(attacker)
		s.units.append(target)
		attacker.intent = Intent.use_action(atk.id, target.id)
		return s

	var deps := _deps(actions_by_id, 10.0)
	var a: CombatState = make_state.call(6)
	var b: CombatState = make_state.call(6)
	for i in 5:
		CombatSim.step(a, deps)
		CombatSim.step(b, deps)

	assert_eq(a.events.size(), b.events.size(), "same seed, same terrain, same event count")
	for i in a.events.size():
		var ea: CombatEvent = a.events[i]
		var eb: CombatEvent = b.events[i]
		assert_eq(ea.kind, eb.kind)
		assert_eq(ea.amount, eb.amount)
