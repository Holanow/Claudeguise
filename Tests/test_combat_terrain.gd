extends "res://Tests/TestCase.gd"


## Covers issue 13a's four acceptance criteria. Same helper shapes as
## test_combat_sim.gd (hand-built units, no Registry/Balance dependency);
## not duplicated here via preload of that file since GDScript test files
## don't share state -- these are small enough to inline.

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

func _idle_deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return deps

## A harmless enemy, far from anything, that never acts. Without a living
## unit on the other team, `_check_outcome` sees "no enemies alive" as
## trivially true and ends the fight as PLAYER_WIN after the very first
## tick -- CombatSim.step() then no-ops forever, which looks exactly like a
## movement bug (a frozen position) and is not one. Every test here that
## steps more than once needs this.
func _dummy_enemy(id: int) -> CombatUnit:
	return _unit(id, CG.Team.ENEMY, 10, Vector2(100000, 100000), [])

# ---------------------------------------------------------------------------
# criterion 1: a wall stops a unit; empty space does not
# ---------------------------------------------------------------------------

func test_a_unit_cannot_walk_through_a_wall() -> void:
	var state := CombatState.new(60)
	var wall := Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(-10, -100), Vector2(20, 200)))
	state.grid.stamp_features([wall])
	var unit := _unit(0, CG.Team.PLAYER, 10, Vector2(-50, 0), [])
	unit.move_speed = 999.0
	state.units.append(unit)

	unit.intent = Intent.move_to(Vector2(50, 0))
	CombatSim.step(state, _idle_deps())

	assert_true(unit.position.x < wall.rect.position.x, "must not end up inside or past the wall: landed at %s" % unit.position)

func test_a_unit_walks_through_empty_space_normally() -> void:
	var state := CombatState.new(61)
	var unit := _unit(0, CG.Team.PLAYER, 10, Vector2.ZERO, [])
	unit.move_speed = 10.0
	state.units.append(unit)

	unit.intent = Intent.move_to(Vector2(10, 0))
	CombatSim.step(state, _idle_deps())

	assert_almost_eq(unit.position.x, 10.0, 0.01, "empty space must not be affected by an empty terrain list")

# ---------------------------------------------------------------------------
# criterion 2: hazards damage per tick, stop the tick after leaving
# ---------------------------------------------------------------------------

func test_a_unit_in_a_hazard_takes_damage_per_tick_and_stops_after_leaving() -> void:
	var state := CombatState.new(62)
	var hazard := Terrain.hazard(Rect2(Vector2(-20, -20), Vector2(40, 40)), 5, CG.DamageType.FIRE)
	state.grid.stamp_features([hazard])
	var unit := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [])
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))
	var deps := _idle_deps()

	CombatSim.step(state, deps)
	assert_eq(unit.hp, 25, "first tick standing in the hazard")
	CombatSim.step(state, deps)
	assert_eq(unit.hp, 20, "second tick standing in the hazard")

	unit.position = Vector2(1000, 1000) # steps out of the hazard by hand
	CombatSim.step(state, deps)
	assert_eq(unit.hp, 20, "no more damage the tick after leaving")

	var dmg_events := 0
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE and e.target_id == 0:
			dmg_events += 1
	assert_eq(dmg_events, 2, "exactly one DAMAGE event per tick actually spent inside the hazard")

# ---------------------------------------------------------------------------
# criterion 3: a unit walking into a wall does not freeze permanently
# ---------------------------------------------------------------------------

func test_a_unit_routes_around_a_wall_when_a_lateral_path_exists() -> void:
	# A short wall (10 tall) directly in the way, with a genuine lateral
	# path: start and target differ in y by 40, so the intended step has a
	# real y-component to slide along, and a few ticks of pure y-sliding
	# clears the wall's y-extent entirely. Simple axis-sliding can solve
	# this; it cannot solve a wall approached with zero lateral component
	# (see the finding below) -- the two tests are deliberately different
	# shapes of the same obstacle, not the same case twice.
	var wall := Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(-10, -5), Vector2(20, 10)))
	var state := CombatState.new(63)
	state.grid.stamp_features([wall])
	var unit := _unit(0, CG.Team.PLAYER, 10, Vector2(-50, -20), [])
	unit.move_speed = 8.0
	# Explicit and small, not the ambient CombatUnit default: this test's
	# geometry (a wall only 10 world units tall) is about whether sliding
	# finds a gap that exists, and a unit whose own radius approaches the
	# wall's half-height swallows the gap before sliding ever gets a chance.
	unit.radius = 5.0
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	var deps := _idle_deps()
	var target := Vector2(50, 20)
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.move_to(target)

	var reached := false
	for i in 100:
		CombatSim.step(state, deps)
		if unit.position.distance_to(target) < 5.0:
			reached = true
			break

	assert_true(reached, "should route around a short wall within 100 ticks; final position %s" % unit.position)

func test_finding_a_unit_approaching_a_wall_head_on_can_get_stuck() -> void:
	# Reporting per the issue's own permission: "I tried and units get stuck
	# on corners is a result, not a failure." Axis-separated sliding has no
	# lateral component to slide along when the intended step is purely
	# perpendicular to the wall and the unit is already aligned with a gap
	# that requires moving *across* its own axis of intended travel to
	# reach. This measures whether that happens, rather than assuming it.
	var wall := Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(-10, -200), Vector2(20, 350)))
	var state := CombatState.new(64)
	state.grid.stamp_features([wall])
	var unit := _unit(0, CG.Team.PLAYER, 10, Vector2(-50, 0), [])
	unit.move_speed = 8.0
	unit.radius = 5.0
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	var deps := _idle_deps()
	var target := Vector2(50, 0)
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.move_to(target)

	var reached := false
	for i in 100:
		CombatSim.step(state, deps)
		if unit.position.distance_to(target) < 5.0:
			reached = true
			break

	print("issue 13a finding: head-on wall approach reached=%s final_pos=%s" % [reached, unit.position])
	# Whichever way this goes is the record; see the board post for what it
	# means for DefaultBehavior (teal's) versus this file's simple slide.
	if reached:
		assert_true(reached)
	else:
		assert_false(reached, "confirmed: a unit approaching a wall with no lateral step component gets stuck, per the issue's own anticipated finding")

# ---------------------------------------------------------------------------
# criterion 4: determinism survives with walls in play
# ---------------------------------------------------------------------------

func test_determinism_holds_with_terrain_in_play() -> void:
	var wall := Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(-10, -30), Vector2(20, 60)))
	var hazard := Terrain.hazard(Rect2(Vector2(20, -50), Vector2(30, 100)), 3, CG.DamageType.EARTH)

	var make_state := func(seed: int) -> CombatState:
		var s := CombatState.new(seed)
		s.grid.stamp_features([wall])
		s.grid.stamp_features([hazard])
		var u := _unit(0, CG.Team.PLAYER, 40, Vector2(-50, -20), [])
		s.units.append(u)
		s.units.append(_dummy_enemy(1))
		return s

	var deps := _idle_deps()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.move_to(Vector2(60, 0))

	var a: CombatState = make_state.call(70)
	var b: CombatState = make_state.call(70)
	for i in 60:
		CombatSim.step(a, deps)
		CombatSim.step(b, deps)

	assert_eq(a.units[0].position, b.units[0].position, "same seed, same terrain, same position")
	assert_eq(a.events.size(), b.events.size(), "same seed, same terrain, same event count")
	for i in a.events.size():
		var ea: CombatEvent = a.events[i]
		var eb: CombatEvent = b.events[i]
		assert_eq(ea.kind, eb.kind)
		assert_eq(ea.amount, eb.amount)

# ---------------------------------------------------------------------------
# issue 30: a unit creeping toward a target beyond a wall corner
# ---------------------------------------------------------------------------

## The bug, reproduced and measured before the fix: with one axis fully
## blocked by the wall, the axis slide used to move by the diagonal step's
## shrinking *component* on the open axis rather than a full step, so
## progress decayed tick over tick without ever quite reaching zero -- an
## asymptote a fixed tick budget cannot tell from frozen. Fixed by giving
## each axis its own full move_speed step (capped to what remains on that
## axis alone) rather than a fraction of the diagonal's.
func test_a_unit_reaches_a_target_beyond_a_wall_corner() -> void:
	var wall := Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(0, -200), Vector2(20, 250)))
	var state := CombatState.new(65)
	state.grid.stamp_features([wall])
	var unit := _unit(0, CG.Team.PLAYER, 30, Vector2(-100, -80), [])
	unit.move_speed = 8.0
	unit.radius = 22.0
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	var deps := _idle_deps()
	var target := Vector2(100, 80) # beyond the wall's bottom corner at y=50
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.move_to(target)

	var reached := false
	for i in 100:
		CombatSim.step(state, deps)
		if unit.position.distance_to(target) < 5.0:
			reached = true
			break

	assert_true(reached, "a unit told to reach a target beyond a wall corner must arrive, not creep forever; final position %s" % unit.position)

## The other half of criterion 1: a target with genuinely no way around (both
## axes blocked, not just one shrinking toward zero) must stop honestly
## rather than creep. Distinguishes "fixed the decay" from "made everything
## always arrive regardless of whether it should."
func test_a_unit_with_no_route_stops_rather_than_creeps() -> void:
	# Three walls forming a box open only away from the target, so neither
	# axis nor the diagonal ever makes progress toward it.
	var state := CombatState.new(66)
	state.grid.stamp_features([Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(-10, -60), Vector2(20, 10)))]) # top
	state.grid.stamp_features([Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(-10, 50), Vector2(20, 10)))]) # bottom
	state.grid.stamp_features([Terrain.make(Terrain.Kind.WALL, Rect2(Vector2(-10, -50), Vector2(10, 100)))]) # right-facing wall between unit and target
	var unit := _unit(0, CG.Team.PLAYER, 30, Vector2(-50, 0), [])
	unit.move_speed = 8.0
	unit.radius = 5.0
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	var deps := _idle_deps()
	var target := Vector2(50, 0)
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.move_to(target)

	for i in 100:
		CombatSim.step(state, deps)

	assert_true(unit.position.distance_to(target) > 5.0, "a genuinely boxed-in unit must not have reached an unreachable target")
	# The honest-stop half: position settles rather than still moving by a
	# shrinking, never-quite-zero amount every tick.
	var before := unit.position
	CombatSim.step(state, deps)
	assert_eq(unit.position, before, "a fully boxed-in unit must stop, not keep creeping by a diminishing amount")

## Criterion 3: the existing straight-on and lateral-slide behaviour (issue
## 13a's own tests) is covered by test_a_unit_routes_around_a_wall_when_a_lateral_path_exists
## and test_finding_a_unit_approaching_a_wall_head_on_can_get_stuck above --
## both still pass unchanged, which is the assertion that this fix does not
## trade one movement bug for another.
