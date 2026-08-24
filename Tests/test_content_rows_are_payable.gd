extends "res://Tests/TestCase.gd"


## Issue 488: a library row a rolled pawn can never pay for. `warrior_execute`
## was gated at `self_resource_at_least 40` against a Warrior ceiling of
## exactly 40, so 382 of 500 rolled Warriors could not fire it and 62 more
## could only at exactly full Rage.

const RESOURCE_OPS := [&"self_resource_at_least", &"self_resource_at_least_fraction"]

## The lowest ceiling the roller can produce for a class: every rolled
## attribute on its own floor.
func _floor_pawn(class_id: StringName) -> PawnData:
	var pawn := PawnFactory.make_starter_pawn(class_id, &"p", String(class_id))
	for a in PawnFactory.ROLLED_ATTRIBUTES:
		pawn.attribute_bonus[a] = PawnFactory.attribute_floor(pawn.pawn_class, a) - pawn.pawn_class.attribute(a)
	return pawn

## What a resource condition demands of a pawn with this ceiling.
func _requirement(block: PlanBlock, ceiling: int) -> int:
	if block.op == &"self_resource_at_least_fraction":
		return int(ceil(float(ceiling) * float(block.args.get("fraction", 1.0))))
	return int(block.args.get("amount", 0))

func _resource_rows(class_id: StringName) -> Array:
	var out := []
	for p in PresetPlans.for_class(class_id):
		if p.condition != null and RESOURCE_OPS.has(p.condition.op):
			out.append(p)
	return out

# ---------------------------------------------------------------------------
# the standing guard
# ---------------------------------------------------------------------------

## The relationship, never today's constants: a row must be reachable by the
## weakest pawn of its own class that the roller can build. A threshold pinned
## to a number here would be the widening trap of #144 waiting to happen.
func test_every_resource_gated_row_is_reachable_by_the_weakest_roll() -> void:
	var checked := 0
	for cid in Registry.all_class_ids():
		var ceiling := Balance.max_resource(_floor_pawn(cid))
		for plan in _resource_rows(cid):
			checked += 1
			assert_true(_requirement(plan.condition, ceiling) <= ceiling,
				"%s asks for %d and the weakest rolled %s can only hold %d, so that row never fires" % [
					plan.id, _requirement(plan.condition, ceiling), cid, ceiling])
	assert_true(checked > 0, "no resource-gated row was found at all -- this guard is measuring nothing")

## A fixed-amount row cannot land on a class's ceiling by coincidence again:
## the zero margin is the defect, not the value that produced it.
func test_no_fixed_amount_row_sits_on_its_own_classes_ceiling() -> void:
	for cid in Registry.all_class_ids():
		var ceiling := Balance.max_resource(PawnFactory.make_starter_pawn(cid, &"p", String(cid)))
		for plan in _resource_rows(cid):
			if plan.condition.op != &"self_resource_at_least":
				continue
			assert_true(int(plan.condition.args.get("amount", 0)) < ceiling,
				"%s asks for exactly what a fixed %s can hold (%d), which fires only on a full pool and only while two independent numbers stay equal" % [
					plan.id, cid, ceiling])

# ---------------------------------------------------------------------------
# the op itself
# ---------------------------------------------------------------------------

func _unit(ceiling: int, resource: int) -> CombatUnit:
	var u := CombatUnit.new()
	u.resource_max = ceiling
	u.resource = resource
	return u

## `condition_holds` takes a Plan, so a bare condition needs one around it.
func _gated(op: StringName, args: Dictionary) -> Plan:
	var b := PlanBlock.new()
	b.kind = PlanBlock.Kind.CONDITION
	b.op = op
	b.args = args
	var plan := Plan.new()
	plan.id = &"probe"
	plan.condition = b
	return plan

func _fraction(f: float) -> Plan:
	return _gated(&"self_resource_at_least_fraction", {"fraction": f})

func test_the_fraction_is_read_against_the_pawns_own_ceiling() -> void:
	assert_true(PlanInterpreter.condition_holds(null, _unit(30, 30), _fraction(1.0)))
	assert_false(PlanInterpreter.condition_holds(null, _unit(30, 29), _fraction(1.0)))
	assert_true(PlanInterpreter.condition_holds(null, _unit(120, 120), _fraction(1.0)))
	assert_false(PlanInterpreter.condition_holds(null, _unit(120, 119), _fraction(1.0)))

## A half-full pool rounds up, so a 5-point pool asks for 3 rather than 2.5.
func test_a_part_pool_rounds_up() -> void:
	assert_false(PlanInterpreter.condition_holds(null, _unit(5, 2), _fraction(0.5)))
	assert_true(PlanInterpreter.condition_holds(null, _unit(5, 3), _fraction(0.5)))

func test_the_row_reads_as_a_percentage_in_the_plan_editor() -> void:
	assert_eq(PlanInterpreter.describe_op(&"self_resource_at_least_fraction", {"fraction": 1.0}),
		"self resource at least 100%")
	assert_eq(PlanInterpreter.describe_op(&"self_resource_at_least_fraction", {"fraction": 0.5}),
		"self resource at least 50%")

## The old op stays, untouched: plans are authored data and a reinterpreted op
## silently rewrites every plan that already carries it.
func test_the_absolute_op_still_exists_and_still_means_an_absolute_amount() -> void:
	var plan := _gated(&"self_resource_at_least", {"amount": 40})
	assert_true(PlanInterpreter.condition_holds(null, _unit(999, 40), plan))
	assert_false(PlanInterpreter.condition_holds(null, _unit(999, 39), plan))

func test_the_new_op_has_an_editable_argument_shape() -> void:
	var shape: Dictionary = PlanInterpreter.CONDITION_ARG_SHAPE.get(&"self_resource_at_least_fraction", {})
	assert_eq(shape.get("kind", ""), "fraction",
		"the plan editor builds its value editor from this, and an unshaped op gets no editor at all")
