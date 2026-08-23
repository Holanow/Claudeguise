extends "res://Tests/TestCase.gd"


## Issue 97: the MOVEMENT block has to be readable in the plan editor. It
## rendered as "unknown op 'keep_distance'" on the one screen meant to explain
## it, because `describe_op` had no case for it.

func test_keep_distance_has_a_player_facing_sentence() -> void:
	assert_eq(PlanInterpreter.describe_op(&"keep_distance", {"range": 120.0}),
		"hold 120 units from the target, on ground that does not harm")

## Range 0 is a charge, not "hold 0 units away", and the sentence has to say so.
func test_keep_distance_at_zero_reads_as_a_charge() -> void:
	assert_eq(PlanInterpreter.describe_op(&"keep_distance", {"range": 0.0}),
		"close to the target")

## The negative half, and the one that catches the next op added to
## `MOVEMENT_OPS` without a sentence or an arg shape.
func test_every_movement_op_is_describable_and_editable() -> void:
	for op in PlanInterpreter.MOVEMENT_OPS:
		assert_true(PlanInterpreter.describe_op(op, {}).find("unknown op") == -1,
			"'%s' renders as an unknown op in the plan editor" % op)
		assert_true(PlanInterpreter.MOVEMENT_ARG_SHAPE.has(op),
			"the editor cannot build a value editor for '%s' without an arg shape" % op)

## The arg shape has to name the key the interpreter actually reads, or the
## editor writes a number the block ignores. `_run_movement` reads "range".
func test_the_arg_shape_names_the_key_the_interpreter_reads() -> void:
	var shape: Dictionary = PlanInterpreter.MOVEMENT_ARG_SHAPE[&"keep_distance"]
	assert_eq(shape["key"], "range")
	assert_true(int(shape["step"]) > 0, "a step of 0 makes the SpinBox unusable")

## Issue 261's trap, one screen over: a SpinBox step that cannot land on an
## authored value draws a number the plan does not hold.
func test_the_step_can_express_the_default() -> void:
	var shape: Dictionary = PlanInterpreter.MOVEMENT_ARG_SHAPE[&"keep_distance"]
	var step := float(shape["step"])
	var default_value := float(shape["default"])
	assert_almost_eq(fmod(default_value, step), 0.0, 0.0001,
		"the default %0.1f does not sit on the step of %0.1f" % [default_value, step])
