extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const Plan := preload("res://Scripts/Core/Plan.gd")
const PlanBlock := preload("res://Scripts/Core/PlanBlock.gd")
const PlanInterpreter := preload("res://Scripts/Plans/PlanInterpreter.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")

## PlanInterpreter tested entirely against hand-built CombatState, per issue
## 2's note that this does not need CombatSim to be working.

func _state_with(a: CombatUnit, b: CombatUnit) -> CombatState:
	var state := CombatState.new(0)
	state.units.append(a)
	state.units.append(b)
	return state

func _melee_unit(id: int, team: CG.Team, pos: Vector2, hp_frac: float = 1.0) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.position = pos
	u.hp_max = 100
	u.hp = int(100.0 * hp_frac)
	u.resource_max = 100
	u.resource = 0
	u.focus_id = -1
	return u

func _block(kind: PlanBlock.Kind, op: StringName, args: Dictionary = {}) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = kind
	b.op = op
	b.args = args
	return b

func _plan(id: StringName, condition: PlanBlock, blocks: Array[PlanBlock]) -> Plan:
	var p := Plan.new()
	p.id = id
	p.condition = condition
	p.blocks = blocks
	return p


func test_condition_holds_null_condition_always_true() -> void:
	var self_unit := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var state := _state_with(self_unit, _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0)))
	var plan := _plan(&"p", null, [])
	assert_true(PlanInterpreter.condition_holds(state, self_unit, plan))


func test_condition_self_hp_below_fraction() -> void:
	var hurt := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO, 0.2)
	var state := _state_with(hurt, _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0)))
	var plan := _plan(&"p", _block(PlanBlock.Kind.CONDITION, &"self_hp_below_fraction", {"fraction": 0.5}), [])
	assert_true(PlanInterpreter.condition_holds(state, hurt, plan))

	var healthy := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO, 1.0)
	var state2 := _state_with(healthy, _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0)))
	assert_false(PlanInterpreter.condition_holds(state2, healthy, plan))


func test_decide_fires_and_tags_source_plan() -> void:
	var attacker := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var target := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	var state := _state_with(attacker, target)

	var pawn_class := ClassDef.new()
	pawn_class.id = &"testclass"
	var pawn := PawnData.new()
	pawn.pawn_class = pawn_class
	pawn.plans = [
		_plan(&"strike_nearest", null, [
			_block(PlanBlock.Kind.TARGETING, &"target_nearest_enemy"),
			_block(PlanBlock.Kind.ACTION, &"use_action", {"action_id": &"warrior_strike"}),
		]),
	]
	attacker.pawn = pawn

	var intent: Intent = PlanInterpreter.decide(state, attacker)
	assert_not_null(intent)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.action_id, &"warrior_strike")
	assert_eq(intent.target_id, target.id)
	assert_eq(intent.source_plan, &"strike_nearest")


func test_decide_returns_null_when_no_plan_fires() -> void:
	var attacker := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var target := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	var state := _state_with(attacker, target)

	var pawn := PawnData.new()
	pawn.pawn_class = ClassDef.new()
	pawn.plans = [
		_plan(&"only_when_hurt", _block(PlanBlock.Kind.CONDITION, &"self_hp_below_fraction", {"fraction": 0.1}), [
			_block(PlanBlock.Kind.TARGETING, &"target_nearest_enemy"),
			_block(PlanBlock.Kind.ACTION, &"use_action", {"action_id": &"warrior_strike"}),
		]),
	]
	attacker.pawn = pawn

	assert_eq(PlanInterpreter.decide(state, attacker), null)


func test_unknown_op_fails_loudly_and_names_the_op_and_plan() -> void:
	var attacker := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var target := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	var state := _state_with(attacker, target)

	var pawn := PawnData.new()
	pawn.pawn_class = ClassDef.new()
	pawn.plans = [
		_plan(&"nonsense_plan", null, [
			_block(PlanBlock.Kind.TARGETING, &"do_a_barrel_roll"),
		]),
	]
	attacker.pawn = pawn

	PlanInterpreter.last_error = ""
	var intent := PlanInterpreter.decide(state, attacker)
	assert_eq(intent, null)
	assert_true(PlanInterpreter.last_error.contains("do_a_barrel_roll"), "error should name the op")
	assert_true(PlanInterpreter.last_error.contains("nonsense_plan"), "error should name the plan")


func test_valid_ops_only_produce_no_error() -> void:
	var attacker := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var target := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	var state := _state_with(attacker, target)

	var pawn := PawnData.new()
	pawn.pawn_class = ClassDef.new()
	pawn.plans = [
		_plan(&"clean_plan", null, [
			_block(PlanBlock.Kind.TARGETING, &"target_nearest_enemy"),
			_block(PlanBlock.Kind.ACTION, &"use_action", {"action_id": &"warrior_strike"}),
		]),
	]
	attacker.pawn = pawn

	PlanInterpreter.last_error = ""
	PlanInterpreter.decide(state, attacker)
	assert_eq(PlanInterpreter.last_error, "")
