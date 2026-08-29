extends "res://Tests/TestCase.gd"


## Issue 759. Blood as a fluid: a bleeding unit's own DoT tick leaves it, a rat
## death leaves it, and it displaces (and is displaced by) water -- the fluid
## that arrives last wins. Nothing bleeds until #746's quiver ships, so this
## tests the production path directly: BLEED pre-set on a unit, exactly the
## state a quiver's hit would leave behind.

const _SEED := 75900

func _unit(id: int, team: CG.Team, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = 500
	u.hp = 500
	u.position = pos
	u.move_speed = 0.0
	return u

func _idle_deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	deps.plan_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return null
	return deps

## A bleeding unit, stacked enough that a DOT tick is guaranteed to land.
func _bleeding_unit(id: int, pos: Vector2) -> CombatUnit:
	var u := _unit(id, CG.Team.PLAYER, pos)
	u.statuses[CG.Status.BLEED] = 9999
	u.status_magnitude[CG.Status.BLEED] = 20.0
	u.status_source[CG.Status.BLEED] = 7
	return u

func _cell_kind(state: CombatState, pos: Vector2) -> int:
	var cell = state.grid.at(TerrainGrid.cell_of(pos))
	return cell.kind if cell != null else -1

func _run(state: CombatState, ticks: int, deps: SimDeps = null) -> void:
	if deps == null:
		deps = _idle_deps()
	for _i in ticks:
		CombatSim.step(state, deps)

# --------------------------------------------------------------- production

func test_a_bleeding_unit_leaves_blood_under_itself() -> void:
	var state := CombatState.new(_SEED)
	var victim := _bleeding_unit(0, Vector2.ZERO)
	state.units.append(victim)
	state.units.append(_unit(1, CG.Team.ENEMY, Vector2(4000.0, 0.0)))
	_run(state, 10)
	assert_eq(_cell_kind(state, victim.position), Terrain.Kind.BLOOD,
		"a BLEED tick that dealt damage must leave blood")

func test_a_unit_with_bleeds_false_leaves_no_blood() -> void:
	var state := CombatState.new(_SEED)
	var victim := _bleeding_unit(0, Vector2.ZERO)
	victim.bleeds = false
	state.units.append(victim)
	state.units.append(_unit(1, CG.Team.ENEMY, Vector2(4000.0, 0.0)))
	_run(state, 10)
	assert_eq(_cell_kind(state, victim.position), -1,
		"the Siege Engine's exception: a machine does not bleed")

func test_a_rat_dying_leaves_blood() -> void:
	var state := CombatState.new(_SEED)
	var rat := _unit(0, CG.Team.ENEMY, Vector2.ZERO)
	rat.enemy_id = &"rat"
	rat.hp = 0
	state.units.append(rat)
	state.units.append(_unit(1, CG.Team.PLAYER, Vector2(4000.0, 0.0)))
	CombatSim._kill_if_dead(state, rat, -1, &"")
	assert_eq(_cell_kind(state, rat.position), Terrain.Kind.BLOOD, "a dead rat leaves a puddle")

func test_a_dying_unit_that_is_not_a_rat_leaves_no_blood() -> void:
	var state := CombatState.new(_SEED)
	var goblin := _unit(0, CG.Team.ENEMY, Vector2.ZERO)
	goblin.enemy_id = &"goblin"
	goblin.hp = 0
	state.units.append(goblin)
	CombatSim._kill_if_dead(state, goblin, -1, &"")
	assert_eq(_cell_kind(state, goblin.position), -1, "only a rat's own death is authored to pool blood")

# ------------------------------------------------------------- displacement

## Water arrives onto blood: the puddle is gone, water is there instead.
func test_water_painted_onto_blood_leaves_water() -> void:
	var state := CombatState.new(_SEED)
	var blood := TerrainGrid.Cell.new()
	blood.kind = Terrain.Kind.BLOOD
	var c := TerrainGrid.cell_of(Vector2.ZERO)
	state.grid.stamp_rect(TerrainGrid.Layer.EFFECTS, TerrainGrid.rect_of(c), blood)
	assert_eq(_cell_kind(state, Vector2.ZERO), Terrain.Kind.BLOOD)

	var water := TerrainGrid.Cell.new()
	water.kind = Terrain.Kind.WATER
	state.grid.stamp_rect(TerrainGrid.Layer.EFFECTS, TerrainGrid.rect_of(c), water)
	assert_eq(_cell_kind(state, Vector2.ZERO), Terrain.Kind.WATER,
		"the fluid that arrives last wins: water over blood leaves water")

## Blood arrives onto water: the pool is gone, blood is there instead --
## the same rule, the other direction.
func test_blood_painted_onto_water_leaves_blood() -> void:
	var state := CombatState.new(_SEED)
	var water := TerrainGrid.Cell.new()
	water.kind = Terrain.Kind.WATER
	var c := TerrainGrid.cell_of(Vector2.ZERO)
	state.grid.stamp_rect(TerrainGrid.Layer.EFFECTS, TerrainGrid.rect_of(c), water)
	assert_eq(_cell_kind(state, Vector2.ZERO), Terrain.Kind.WATER)

	CombatSim._leave_blood(state, 7, [c])
	assert_eq(_cell_kind(state, Vector2.ZERO), Terrain.Kind.BLOOD,
		"the fluid that arrives last wins: blood over water leaves blood")

## Blood never covers (and so never silently disables) a fire hazard -- that
## stays water's alone, per #767's own note that this asymmetry is deliberate.
func test_blood_does_not_paint_over_a_hazard() -> void:
	var state := CombatState.new(_SEED)
	var fire := Terrain.hazard(Rect2(-50.0, -50.0, 100.0, 100.0), 0, CG.DamageType.FIRE)
	state.grid.stamp_features([fire])
	var c := TerrainGrid.cell_of(Vector2.ZERO)
	CombatSim._leave_blood(state, 7, [c])
	assert_eq(_cell_kind(state, Vector2.ZERO), Terrain.Kind.HAZARD,
		"blood must not cover, and so disable, a burning tile")
