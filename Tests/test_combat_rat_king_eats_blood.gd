extends "res://Tests/TestCase.gd"


## Issue 759. `ConsumeGroundEffect` is general -- eats ground of a declared
## `kind` under the caster and heals a fraction of max hp -- and the Rat
## King's own plan row is the first thing that uses it: eat blood below 50%
## hp, a row the player can read and change like any other.

const _SEED := 75901

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

func _blood_at(state: CombatState, pos: Vector2) -> void:
	var blood := TerrainGrid.Cell.new()
	blood.kind = Terrain.Kind.BLOOD
	var c := TerrainGrid.cell_of(pos)
	state.grid.stamp_rect(TerrainGrid.Layer.EFFECTS, TerrainGrid.rect_of(c), blood)

# ------------------------------------------------------- ConsumeGroundEffect

func _consume_action(kind: Terrain.Kind, fraction: float) -> ActionDef:
	var fx := ConsumeGroundEffect.new()
	fx.kind = kind
	fx.heal_fraction_of_max_hp = fraction
	var a := ActionDef.new()
	a.id = &"fixture_consume"
	a.targeting = ActionTargeting.new()
	a.targeting.targets_self = true
	a.effects = [fx] as Array[AbilityEffect]
	return a

func test_consume_ground_heals_and_clears_the_cell() -> void:
	var action := _consume_action(Terrain.Kind.BLOOD, 0.15)
	var unit := _unit(0, CG.Team.ENEMY, Vector2.ZERO)
	unit.hp = 100
	unit.actions = [action.id] as Array[StringName]
	var state := CombatState.new(_SEED)
	state.units.append(unit)
	_blood_at(state, unit.position)

	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName) -> ActionDef: return action if id == action.id else null
	CombatSim._apply_action_effect(state, unit, unit, action, deps)

	assert_eq(unit.hp, 175, "15% of 500 max hp recovered")
	var c := TerrainGrid.cell_of(unit.position)
	assert_eq(state.grid.at(c), null, "the blood is eaten, not left behind")

func test_consume_ground_on_the_wrong_kind_does_nothing() -> void:
	var action := _consume_action(Terrain.Kind.BLOOD, 0.15)
	var unit := _unit(0, CG.Team.ENEMY, Vector2.ZERO)
	unit.hp = 100
	var state := CombatState.new(_SEED)
	state.units.append(unit)
	var water := TerrainGrid.Cell.new()
	water.kind = Terrain.Kind.WATER
	var c := TerrainGrid.cell_of(unit.position)
	state.grid.stamp_rect(TerrainGrid.Layer.EFFECTS, TerrainGrid.rect_of(c), water)

	var deps := SimDeps.new()
	CombatSim._apply_action_effect(state, unit, unit, action, deps)
	assert_eq(unit.hp, 100, "water is not blood; nothing is eaten")
	assert_eq(state.grid.at(c).kind, Terrain.Kind.WATER, "and the water is left alone")

# ------------------------------------------------------------- the Rat King

## The row itself, per #728: the priority is authored on the enemy, not
## hardcoded in the simulation.
func test_the_rat_king_carries_an_eat_blood_row_below_half_health() -> void:
	var def := EnemyLibrary.get_enemy(&"rat_king")
	assert_true(def != null and not def.plans.is_empty(), "the Rat King has no plan rows at all")
	var found := false
	for plan in def.plans:
		for block in plan.blocks:
			if block is UseActionBlock and block.action != null and block.action.id == &"rat_king_eat_blood":
				found = true
	assert_true(found, "no row on the Rat King uses rat_king_eat_blood")

## The production path: a real Rat King, below half health, standing on
## blood, actually eats it and heals.
func test_the_rat_king_eats_blood_below_half_health() -> void:
	var def := EnemyLibrary.get_enemy(&"rat_king")
	var king := _unit(0, CG.Team.ENEMY, Vector2.ZERO)
	king.enemy_id = &"rat_king"
	king.hp_max = def.hp_max
	king.hp = int(def.hp_max * 0.4)
	king.actions = def.actions.duplicate()
	king.enemy_plans = def.plans.duplicate()
	var state := CombatState.new(_SEED)
	state.units.append(king)
	state.units.append(_unit(1, CG.Team.PLAYER, Vector2(4000.0, 0.0)))
	_blood_at(state, king.position)

	var deps := SimDeps.new()
	var hp_before := king.hp
	for _i in 60:
		CombatSim.step(state, deps)
	assert_true(king.hp > hp_before, "below half health, standing on blood, the King must have eaten")

## Above half health the row must not fire even with blood underfoot -- the
## priority is real, not decorative.
func test_the_rat_king_does_not_eat_blood_above_half_health() -> void:
	var def := EnemyLibrary.get_enemy(&"rat_king")
	var king := _unit(0, CG.Team.ENEMY, Vector2.ZERO)
	king.enemy_id = &"rat_king"
	king.hp_max = def.hp_max
	king.hp = def.hp_max
	king.actions = def.actions.duplicate()
	king.enemy_plans = def.plans.duplicate()
	var state := CombatState.new(_SEED)
	state.units.append(king)
	state.units.append(_unit(1, CG.Team.PLAYER, Vector2(4000.0, 0.0)))
	_blood_at(state, king.position)

	var deps := SimDeps.new()
	for _i in 30:
		CombatSim.step(state, deps)
	var c := TerrainGrid.cell_of(king.position)
	assert_eq(state.grid.at(c).kind, Terrain.Kind.BLOOD, "at full health the blood is left untouched")
