extends "res://Tests/TestCase.gd"


## Issue 671: `EnemyDef.plans`, and the two seams it flows through --
## `CombatSim._build_enemy_unit` copying it onto `CombatUnit.enemy_plans`, and
## `_decide_phase` reaching `PlanInterpreter.decide` for an enemy that carries
## rows instead of going straight to `DefaultPlan`, exactly as a pawn already
## does. Empty `enemy_plans` (every enemy before this issue) must reach
## `DefaultPlan` exactly as before.

# ---------------------------------------------------------------------------
# _decide_phase's gate, isolated with spy deps -- no content, no PlanInterpreter
# ---------------------------------------------------------------------------

func _idle_unit(id: int, team: CG.Team) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = 10
	u.hp = 10
	return u

func _spy_deps(plan_result: Intent, default_result: Intent) -> SimDeps:
	var deps := SimDeps.new()
	deps.plan_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return plan_result
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return default_result
	return deps

func test_a_pawn_still_reaches_plan_decide_first() -> void:
	var state := CombatState.new(671)
	var unit := _idle_unit(0, CG.Team.PLAYER)
	unit.pawn = PawnData.new()
	state.units.append(unit)
	var from_plan := Intent.idle(&"from_plan")
	var from_default := Intent.idle(&"from_default")
	CombatSim.step(state, _spy_deps(from_plan, from_default))
	assert_eq(unit.intent.source_plan, &"from_plan", "a pawn must still reach plan_decide first, unchanged")

func test_an_enemy_with_no_plans_goes_straight_to_default_decide() -> void:
	var state := CombatState.new(672)
	var unit := _idle_unit(0, CG.Team.ENEMY) # pawn == null, enemy_plans empty: every enemy before issue 671
	state.units.append(unit)
	var from_plan := Intent.idle(&"from_plan")
	var from_default := Intent.idle(&"from_default")
	CombatSim.step(state, _spy_deps(from_plan, from_default))
	assert_eq(unit.intent.source_plan, &"from_default", "an enemy with no authored rows must never reach plan_decide")

func test_an_enemy_carrying_plans_reaches_plan_decide() -> void:
	var state := CombatState.new(673)
	var unit := _idle_unit(0, CG.Team.ENEMY)
	unit.enemy_plans = [Plan.new()] # non-empty is the whole trigger
	state.units.append(unit)
	var from_plan := Intent.idle(&"from_plan")
	var from_default := Intent.idle(&"from_default")
	CombatSim.step(state, _spy_deps(from_plan, from_default))
	assert_eq(unit.intent.source_plan, &"from_plan", "an enemy carrying rows must reach plan_decide, same as a pawn")

func test_an_enemy_carrying_plans_still_falls_through_when_none_fire() -> void:
	var state := CombatState.new(674)
	var unit := _idle_unit(0, CG.Team.ENEMY)
	unit.enemy_plans = [Plan.new()]
	state.units.append(unit)
	var from_default := Intent.idle(&"from_default")
	CombatSim.step(state, _spy_deps(null, from_default)) # plan_decide returns null: nothing fired
	assert_eq(unit.intent.source_plan, &"from_default", "null from plan_decide must still fall through to default_decide")

# ---------------------------------------------------------------------------
# PlanInterpreter.decide itself: enemy_plans has no WIS budget, every row runs
# ---------------------------------------------------------------------------

func _always_idle_row(name: StringName) -> Plan:
	var p := Plan.new()
	p.id = name
	p.condition = null # null condition always holds, per Plan.gd's own doc comment
	p.blocks = []
	return p

func test_enemy_plans_run_every_row_with_no_budget_cap() -> void:
	var state := CombatState.new(675)
	var unit := CombatUnit.new()
	unit.id = 0
	# A row with no blocks resolves to no action and no movement, so
	# `_run_blocks` returns null and PlanInterpreter.decide must still reach
	# the LAST row rather than stopping at some pawn-only budget index.
	unit.enemy_plans = [_always_idle_row(&"a"), _always_idle_row(&"b"), _always_idle_row(&"c")]
	var intent := PlanInterpreter.decide(state, unit)
	assert_eq(intent, null, "every row here resolves to nothing, so decide() must return null having tried all three")

# ---------------------------------------------------------------------------
# end to end: EnemyDef.plans -> CombatUnit.enemy_plans via CombatSim.build()
# ---------------------------------------------------------------------------

func _bare_action(id: StringName) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 1
	a.recover_ticks = 1
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 999.0
	return a

func _party_deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.max_hp = func(_p: PawnData) -> int: return 20
	deps.max_resource = func(_p: PawnData) -> int: return 0
	deps.move_speed = func(_p: PawnData) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _r = null) -> float: return 0.0
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	return deps

func test_build_copies_enemy_def_plans_onto_the_unit() -> void:
	var special := _bare_action(&"special")
	var plan := Plan.new()
	plan.id = &"row"
	plan.condition = BlockCatalog.condition(&"always")
	var target_block: TargetingBlock = BlockCatalog.targeting(&"target_nearest_enemy")
	var use_block := UseActionBlock.new()
	use_block.action_id = &"special"
	plan.blocks = [target_block, use_block] as Array[PlanBlock]

	var enemy_def := EnemyDef.new()
	enemy_def.id = &"test_sellsword_fixture"
	enemy_def.hp_max = 40
	enemy_def.actions = [&"special"]
	enemy_def.plans = [plan]

	var encounter := Encounter.new()
	encounter.party_spawns = [Vector2(-100, 0)]
	encounter.enemy_spawns = [{"enemy_id": &"test_sellsword_fixture", "position": Vector2(50, 0)}]

	var deps := _party_deps()
	deps.action_lookup = func(id: StringName): return special if id == &"special" else null
	deps.enemy_lookup = func(_id: StringName): return enemy_def
	var default_ran_for_enemy := [false] # single-element array: a mutable capture
	deps.default_decide = func(_s: CombatState, u: CombatUnit) -> Intent:
		if u.enemy_id == &"test_sellsword_fixture":
			default_ran_for_enemy[0] = true
		return Intent.idle()

	var state := CombatSim.build([PawnData.new()], encounter, 671, deps)
	var enemy: CombatUnit = state.units[1]
	assert_eq(enemy.enemy_plans.size(), 1, "CombatSim.build must copy EnemyDef.plans onto the unit")

	CombatSim.step(state, deps)
	var fired := false
	for e in state.events:
		if e.kind == CG.EventKind.ACTION_START and e.source_id == enemy.id and e.action_id == &"special":
			fired = true
	assert_true(fired, "the authored row's action must fire instead of DefaultPlan's own pick")
	assert_false(default_ran_for_enemy[0], "DefaultPlan must not run at all for an enemy whose authored row fired")
