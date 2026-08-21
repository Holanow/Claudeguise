extends "res://Tests/TestCase.gd"


## **Issue 384: the ground a pawn stands on, as something a plan can say.** The
## player watched a Geysermancer burn, went to write "stop standing in the fire"
## and the condition vocabulary did not contain the concept.

## Goblins, because they do not taunt: `CombatSim._decide_phase` takes the
## compulsion branch before the plan layer, so a taunter in the room would stop
## every plan being read and mask what this file measures (#379, #381).
func _enemies() -> Array[Dictionary]:
	return [
		{"enemy_id": &"goblin", "position": Vector2(140.0, -40.0)},
		{"enemy_id": &"goblin", "position": Vector2(140.0, 40.0)},
	]

const _SEED := 11
const _SPAWN := Vector2(-120.0, 0.0)

# ---------------------------------------------------------------------------
# The predicate

func test_the_pair_reads_the_ground_under_the_unit_and_nothing_else() -> void:
	var state := CombatState.new(_SEED)
	state.terrain = [Terrain.hazard(Rect2(-10.0, -10.0, 20.0, 20.0), 2, CG.DamageType.FIRE)]
	var unit := _pawn_unit(Vector2.ZERO)
	state.units.append(unit)

	assert_true(_holds(state, unit, &"self_on_harmful_ground"), "standing in the fire")
	assert_false(_holds(state, unit, &"self_on_safe_ground"), "the pair must not both hold")

	unit.position = Vector2(200.0, 200.0)
	assert_false(_holds(state, unit, &"self_on_harmful_ground"), "clean floor")
	assert_true(_holds(state, unit, &"self_on_safe_ground"), "the pair must not both fail")

## The negative half of the shape decision: the op reads
## `CombatSim.standing_harms` rather than owning a second answer, so a hazard
## authored with neither damage nor a status is invisible to a plan for exactly
## the same reason it is invisible to `_avoid_hazard`.
func test_a_decorative_hazard_does_not_hold_the_condition() -> void:
	var state := CombatState.new(_SEED)
	state.terrain = [Terrain.make(Terrain.Kind.HAZARD, Rect2(-10.0, -10.0, 20.0, 20.0))]
	var unit := _pawn_unit(Vector2.ZERO)
	state.units.append(unit)
	assert_false(_holds(state, unit, &"self_on_harmful_ground"), "a hazard that costs nothing is not harmful ground")

func test_the_pair_is_offered_to_the_editor_with_no_argument() -> void:
	for op in [&"self_on_harmful_ground", &"self_on_safe_ground"]:
		assert_true(PlanInterpreter.CONDITION_OPS.has(op), "%s must be in the condition dropdown" % op)
		assert_eq(String(PlanInterpreter.CONDITION_ARG_SHAPE[op].get("kind", "")), "none",
			"%s takes no argument, so the editor must not build a value box for it" % op)
		assert_ne(PlanInterpreter.describe_op(op, {}), "unknown op '%s'" % op,
			"%s needs a sentence, or the plan row reads as a bug" % op)

# ---------------------------------------------------------------------------
# The loop. #381's shape: the edit must reach the simulation.

## Two fights that differ only in which half of the pair gates the row. On
## harmful ground the two must disagree, or the condition never reached the
## fight.
func test_the_two_halves_produce_different_fights_on_harmful_ground() -> void:
	var burning := _fight(&"self_on_harmful_ground", true)
	var safe := _fight(&"self_on_safe_ground", true)
	assert_true(burning["casts"] > 0, "gated on harmful ground while standing on it, the row must fire")
	assert_eq(safe["casts"], 0, "gated on safe ground while standing on harmful ground, the row must never fire")
	assert_ne(burning["signature"], safe["signature"],
		"the same seed produced the same event stream for both halves, so the condition never reached the simulation")

## And the mirror, on clean floor, which is what makes the test above evidence
## about the ground rather than about one op being broken.
func test_the_two_halves_swap_when_the_floor_is_clean() -> void:
	var burning := _fight(&"self_on_harmful_ground", false)
	var safe := _fight(&"self_on_safe_ground", false)
	assert_eq(burning["casts"], 0, "clean floor, so the harmful-ground row must never fire")
	assert_true(safe["casts"] > 0, "clean floor, so the safe-ground row must fire")

func test_the_same_plan_twice_is_the_same_fight() -> void:
	assert_eq(_fight(&"self_on_harmful_ground", true)["signature"], _fight(&"self_on_harmful_ground", true)["signature"],
		"the same plan and seed must replay identically")

# ---------------------------------------------------------------------------
# The constraint recorded on #97, re-measured rather than assumed.

## **#97 recorded that a MOVEMENT block cannot carry a zero-range self-targeted
## action, and #335 fixed it.** `_target_in_range` measures
## `action_target_id(...)`, which is the caster itself for a self-targeted
## action, so distance 0 clears a stated range of 0. This is the first plan
## anybody writes against #384 -- "when standing in fire, move and raise your
## shield" -- so it is asserted here rather than trusted.
func test_a_movement_block_can_carry_a_zero_range_self_buff() -> void:
	var guard := Registry.get_action(&"warrior_guard")
	assert_eq(guard.range_units, 0.0, "the constraint is about a stated range of 0; warrior_guard no longer states one")
	assert_true(guard.targets_self)

	var state := CombatState.new(_SEED)
	var unit := _pawn_unit(Vector2.ZERO)
	unit.actions = [&"warrior_guard"] as Array[StringName]
	unit.resource = 100
	state.units.append(unit)
	var enemy := _pawn_unit(Vector2(120.0, 0.0))
	enemy.id = 1
	enemy.team = CG.Team.ENEMY
	state.units.append(enemy)

	unit.pawn = PawnFactory.make_starter_pawn(&"warrior", &"warrior_0", "Warrior")
	unit.pawn.plans = [_plan(&"self_on_safe_ground", &"warrior_guard", 120.0)] as Array[Plan]

	var intent := PlanInterpreter.decide(state, unit)
	assert_not_null(intent, "the row idled instead of acting")
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION, "in the keep_distance band the row must fire its self-buff")
	assert_eq(intent.target_id, unit.id, "a self-buff lands on the caster whatever the movement block measured")

# ---------------------------------------------------------------------------

## Harmful because it applies a status, not because it deals damage: it has to
## cover the fight for its whole length, and a damaging floor that wide kills
## both halves at different ticks for a reason unrelated to the condition.
func _room_wide_hazard():
	var f = Terrain.make(Terrain.Kind.HAZARD, Rect2(-2000.0, -2000.0, 4000.0, 4000.0))
	f.applies_status = CG.Status.SLOWED
	f.applies_status_enabled = true
	f.status_duration_ticks = 30
	return f

func _holds(state: CombatState, unit: CombatUnit, op: StringName) -> bool:
	var plan := Plan.new()
	plan.id = &"probe"
	plan.condition = _condition(op)
	return PlanInterpreter.condition_holds(state, unit, plan)

func _condition(op: StringName) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = PlanBlock.Kind.CONDITION
	b.op = op
	return b

func _pawn_unit(at: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.position = at
	u.hp_max = 1000
	u.hp = u.hp_max
	return u

## One plan: gate on `op`, aim at the nearest enemy, use `action_id`. A
## `keep_distance` block is added only when `hold` is positive.
func _plan(op: StringName, action_id: StringName, hold: float = 0.0) -> Plan:
	var targeting := PlanBlock.new()
	targeting.kind = PlanBlock.Kind.TARGETING
	targeting.op = &"target_nearest_enemy"
	var action := PlanBlock.new()
	action.kind = PlanBlock.Kind.ACTION
	action.op = &"use_action"
	action.args = {"action_id": action_id}
	var blocks: Array[PlanBlock] = [targeting]
	if hold > 0.0:
		var movement := PlanBlock.new()
		movement.kind = PlanBlock.Kind.MOVEMENT
		movement.op = &"keep_distance"
		movement.args = {"range": hold}
		blocks.append(movement)
	blocks.append(action)

	var plan := Plan.new()
	plan.id = &"ground_row"
	plan.display_name = "Ground row"
	plan.condition = _condition(op)
	plan.blocks = blocks
	return plan

## One fight, with a Warrior carrying exactly one plan gated on `op`.
## `on_hazard` floors the whole room in a harmful surface and nothing else
## changes. Room-wide on purpose: a patch under the spawn is walked off within a
## few ticks by whichever half falls through to `DefaultBehavior`, which would
## make the two halves differ for a reason that is not the condition.
func _fight(op: StringName, on_hazard: bool) -> Dictionary:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"warrior_0", "Warrior")
	var plan := _plan(op, &"warrior_second_wind")
	pawn.plans = [plan] as Array[Plan]

	var encounter := Encounter.new()
	encounter.id = &"test_ground_condition"
	encounter.party_spawns = [_SPAWN] as Array[Vector2]
	encounter.enemy_spawns = _enemies()
	if on_hazard:
		encounter.terrain = [_room_wide_hazard()]

	var state := CombatSim.build([pawn] as Array[PawnData], encounter, _SEED)
	CombatSim.run(state)

	var casts := 0
	var parts := PackedStringArray()
	for e in state.events:
		if e.source_plan == plan.id:
			casts += 1
		parts.append("%d:%d:%d:%d:%s:%d" % [e.tick, e.kind, e.source_id, e.target_id, e.action_id, e.amount])
	return {"casts": casts, "signature": "|".join(parts)}
