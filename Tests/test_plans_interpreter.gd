extends "res://Tests/TestCase.gd"


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

## Issue 269: **these fixtures used to be `ClassDef.new()` bare, and that is no
## longer a pawn that can run a plan.** `decide` now stops at
## `PlanInterpreter.active_plan_count`, which is `Balance.plan_block_budget` --
## the pawn's WIS. A `ClassDef` with an empty `base_attributes` has 0 WIS, so its
## budget is the `maxi(1, ...)` floor of 1 block, and every plan below costs 2.
func _test_class(id: StringName = &"testclass") -> ClassDef:
	var cls := ClassDef.new()
	cls.id = id
	cls.base_attributes = {"WIS": 8}
	return cls


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

	var pawn_class := _test_class()
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
	pawn.pawn_class = _test_class()
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
	pawn.pawn_class = _test_class()
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
	pawn.pawn_class = _test_class()
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


## Issue 21a: describe_op is display-only, called by pike's pawn-inspect
## screen, never by decide()/condition_holds(). Covers every whitelisted op
## plus the unknown-op fallback.
func test_describe_op_covers_every_whitelisted_op() -> void:
	assert_eq(PlanInterpreter.describe_op(&"always", {}), "always")
	assert_eq(PlanInterpreter.describe_op(&"self_hp_below_fraction", {"fraction": 0.35}), "self hp below 35%")
	assert_eq(PlanInterpreter.describe_op(&"ally_below_hp_fraction", {"fraction": 0.5}), "an ally's hp below 50%")
	assert_eq(PlanInterpreter.describe_op(&"self_resource_at_least", {"amount": 60}), "self resource at least 60")
	assert_eq(PlanInterpreter.describe_op(&"enemy_in_range", {"range": 220.0}), "an enemy within 220 units")
	assert_eq(PlanInterpreter.describe_op(&"target_nearest_enemy", {}), "the nearest enemy")
	assert_eq(PlanInterpreter.describe_op(&"target_lowest_hp_fraction_ally", {}), "the ally with the lowest hp")
	assert_eq(PlanInterpreter.describe_op(&"target_lowest_hp_fraction_enemy", {}), "the enemy with the lowest hp")
	assert_eq(PlanInterpreter.describe_op(&"target_self", {}), "self")
	assert_eq(PlanInterpreter.describe_op(&"use_action", {"action_id": &"warrior_strike"}), "use Strike")
	assert_eq(PlanInterpreter.describe_op(&"once", {}), "once")


## Issue 22: CONDITION_ARG_SHAPE used to be InspectPanel.gd's own copy of this
## fact, duplicating what _eval_condition's match statement already encodes.
func test_condition_arg_shape_covers_exactly_the_condition_ops() -> void:
	for op in PlanInterpreter.CONDITION_OPS:
		assert_true(PlanInterpreter.CONDITION_ARG_SHAPE.has(op), "CONDITION_ARG_SHAPE missing an entry for %s" % op)
	for op in PlanInterpreter.CONDITION_ARG_SHAPE.keys():
		assert_true(PlanInterpreter.CONDITION_OPS.has(op), "CONDITION_ARG_SHAPE has an entry for %s, not a real condition op" % op)


func test_describe_op_unknown_op_names_itself_rather_than_going_blank() -> void:
	var described := PlanInterpreter.describe_op(&"do_a_barrel_roll", {})
	assert_true(described.contains("do_a_barrel_roll"), "unknown op description should still name the op")


## Issue 22: a pawn that cannot afford its first plan's action must fall
## through to its second rather than standing still. Two plans, identical
## condition (always), first costs 60, second costs 0 -- the exact shape
## PlanRangeAudit's cousin found on the Abomination.
func _two_plan_pawn() -> PawnData:
	var pawn := PawnData.new()
	pawn.pawn_class = _test_class()
	pawn.plans = [
		_plan(&"expensive_first", null, [
			_block(PlanBlock.Kind.TARGETING, &"target_nearest_enemy"),
			_block(PlanBlock.Kind.ACTION, &"use_action", {"action_id": &"warrior_execute"}),
		]),
		_plan(&"free_second", null, [
			_block(PlanBlock.Kind.TARGETING, &"target_nearest_enemy"),
			_block(PlanBlock.Kind.ACTION, &"use_action", {"action_id": &"warrior_strike"}),
		]),
	]
	return pawn


func test_cannot_afford_first_plan_falls_through_to_second() -> void:
	var attacker := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var target := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	var state := _state_with(attacker, target)
	attacker.pawn = _two_plan_pawn()
	attacker.resource = 0  # warrior_execute costs 60

	var intent := PlanInterpreter.decide(state, attacker)
	assert_not_null(intent)
	assert_eq(intent.action_id, &"warrior_strike", "should fall through to the free plan when it cannot afford the first")
	assert_eq(intent.source_plan, &"free_second")


func test_can_afford_first_plan_uses_it_not_the_second() -> void:
	var attacker := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var target := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	var state := _state_with(attacker, target)
	attacker.pawn = _two_plan_pawn()
	attacker.resource = 60

	var intent := PlanInterpreter.decide(state, attacker)
	assert_not_null(intent)
	assert_eq(intent.action_id, &"warrior_execute", "should use the first plan when it can afford it, priority order intact")
	assert_eq(intent.source_plan, &"expensive_first")


func test_action_on_cooldown_falls_through_same_as_unaffordable() -> void:
	var attacker := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var target := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	var state := _state_with(attacker, target)
	state.tick = 5
	attacker.pawn = _two_plan_pawn()
	attacker.resource = 60  # can afford it...
	attacker.cooldowns[&"warrior_execute"] = 10  # ...but it is still on cooldown until tick 10

	var intent := PlanInterpreter.decide(state, attacker)
	assert_not_null(intent)
	assert_eq(intent.action_id, &"warrior_strike", "should fall through when the action is on cooldown")
	assert_eq(intent.source_plan, &"free_second")


func test_action_off_cooldown_fires_normally() -> void:
	var attacker := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var target := _melee_unit(1, CG.Team.ENEMY, Vector2(10, 0))
	var state := _state_with(attacker, target)
	state.tick = 10
	attacker.pawn = _two_plan_pawn()
	attacker.resource = 60
	attacker.cooldowns[&"warrior_execute"] = 10  # ends exactly at tick 10

	var intent := PlanInterpreter.decide(state, attacker)
	assert_not_null(intent)
	assert_eq(intent.action_id, &"warrior_execute")


# ---------------------------------------------------------------------------
# Issue 87: ally_has_harmful_status / target_ally_with_harmful_status.

func _three(a: CombatUnit, b: CombatUnit, c: CombatUnit) -> CombatState:
	var state := CombatState.new(0)
	state.units.append(a)
	state.units.append(b)
	state.units.append(c)
	return state

func _cleanse_pawn() -> PawnData:
	var cls := _test_class(&"geysermancer")
	cls.starting_actions = [Registry.get_action(&"geyser_cleanse")]
	var pawn := PawnData.new()
	pawn.pawn_class = cls
	pawn.plans = [_plan(
		&"scour",
		_block(PlanBlock.Kind.CONDITION, &"ally_has_harmful_status"),
		[
			_block(PlanBlock.Kind.TARGETING, &"target_ally_with_harmful_status"),
			_block(PlanBlock.Kind.ACTION, &"use_action", {"action_id": &"geyser_cleanse"}),
		]
	)]
	return pawn


func test_ally_has_harmful_status_holds_only_for_a_harmful_one() -> void:
	var caster := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var ally := _melee_unit(1, CG.Team.PLAYER, Vector2(30, 0))
	var enemy := _melee_unit(2, CG.Team.ENEMY, Vector2(100, 0))
	var state := _three(caster, ally, enemy)
	var plan := _plan(&"p", _block(PlanBlock.Kind.CONDITION, &"ally_has_harmful_status"), [])

	assert_false(PlanInterpreter.condition_holds(state, caster, plan), "nobody afflicted")

	ally.statuses[CG.Status.HASTE] = 999
	assert_false(PlanInterpreter.condition_holds(state, caster, plan), "HASTE is not harmful, per CG.is_harmful")

	ally.statuses[CG.Status.POISON] = 999
	assert_true(PlanInterpreter.condition_holds(state, caster, plan))


func test_ally_has_harmful_status_ignores_the_enemy_team() -> void:
	var caster := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var ally := _melee_unit(1, CG.Team.PLAYER, Vector2(30, 0))
	var enemy := _melee_unit(2, CG.Team.ENEMY, Vector2(40, 0))
	enemy.statuses[CG.Status.POISON] = 999
	var state := _three(caster, ally, enemy)
	var plan := _plan(&"p", _block(PlanBlock.Kind.CONDITION, &"ally_has_harmful_status"), [])
	assert_false(PlanInterpreter.condition_holds(state, caster, plan),
		"a poisoned enemy is not a reason to cleanse -- the whole point of the op is that it never aims at one")


func test_ally_has_harmful_status_counts_the_caster_itself() -> void:
	var caster := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	caster.statuses[CG.Status.POISON] = 999
	var ally := _melee_unit(1, CG.Team.PLAYER, Vector2(30, 0))
	var enemy := _melee_unit(2, CG.Team.ENEMY, Vector2(100, 0))
	var state := _three(caster, ally, enemy)
	caster.pawn = _cleanse_pawn()
	caster.resource = 100  # geyser_cleanse costs 10; _melee_unit starts at 0

	var intent := PlanInterpreter.decide(state, caster)
	assert_not_null(intent)
	assert_eq(intent.target_id, caster.id, "a poisoned caster is nearest to itself and scrubs its own affliction")


func test_targeting_picks_the_afflicted_ally_not_the_hurt_one() -> void:
	var caster := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var afflicted := _melee_unit(1, CG.Team.PLAYER, Vector2(30, 0), 1.0)
	afflicted.statuses[CG.Status.POISON] = 999
	var nearly_dead := _melee_unit(2, CG.Team.PLAYER, Vector2(10, 0), 0.05)
	var state := _three(caster, afflicted, nearly_dead)
	state.units.append(_melee_unit(3, CG.Team.ENEMY, Vector2(400, 0)))
	caster.pawn = _cleanse_pawn()
	caster.resource = 100  # geyser_cleanse costs 10; _melee_unit starts at 0

	var intent := PlanInterpreter.decide(state, caster)
	assert_not_null(intent)
	assert_eq(intent.action_id, &"geyser_cleanse")
	assert_eq(intent.target_id, afflicted.id,
		"target_lowest_hp_fraction_ally would have picked unit 2, which has nothing to strip -- measured at 16%% of afflicted ticks in 210 real fights")


func test_the_plan_never_fires_at_a_stale_enemy_focus() -> void:
	# The failure the condition exists to prevent: nobody is afflicted, so
	# targeting finds nothing and leaves focus_id alone -- and focus_id is an
	# enemy, left there by the Blast plan on an earlier tick. If this plan
	# fired anyway it would cleanse an enemy.
	var caster := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var ally := _melee_unit(1, CG.Team.PLAYER, Vector2(30, 0))
	var enemy := _melee_unit(2, CG.Team.ENEMY, Vector2(50, 0))
	var state := _three(caster, ally, enemy)
	caster.pawn = _cleanse_pawn()
	caster.resource = 100  # geyser_cleanse costs 10; _melee_unit starts at 0
	caster.focus_id = enemy.id

	assert_true(PlanInterpreter.decide(state, caster) == null,
		"with nothing to strip the plan must decline entirely, not fire at whatever focus_id still holds")


func test_a_dead_ally_is_not_a_cleanse_target() -> void:
	var caster := _melee_unit(0, CG.Team.PLAYER, Vector2.ZERO)
	var corpse := _melee_unit(1, CG.Team.PLAYER, Vector2(30, 0), 0.0)
	corpse.alive = false
	corpse.statuses[CG.Status.POISON] = 999
	var enemy := _melee_unit(2, CG.Team.ENEMY, Vector2(100, 0))
	var state := _three(caster, corpse, enemy)
	caster.pawn = _cleanse_pawn()
	caster.resource = 100  # geyser_cleanse costs 10; _melee_unit starts at 0

	assert_true(PlanInterpreter.decide(state, caster) == null,
		"state.living() is what both ops read, so a corpse's statuses can never open this plan")
