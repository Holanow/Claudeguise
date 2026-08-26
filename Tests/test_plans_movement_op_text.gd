extends "res://Tests/TestCase.gd"


## Issue 97: the MOVEMENT block has to be readable in the plan editor. It
## rendered as "unknown op 'keep_distance'" on the one screen meant to explain
## it, because the description had no case for it.

func test_keep_distance_has_a_player_facing_sentence() -> void:
	assert_eq(PlanFixtures.block(&"keep_distance", {"range_units": 120.0}).describe(),
		"hold 120 units from the target, on ground that does not harm")

## Range 0 is a charge, not "hold 0 units away", and the sentence has to say so.
func test_keep_distance_at_zero_reads_as_a_charge() -> void:
	assert_eq(PlanFixtures.block(&"keep_distance", {"range_units": 0.0}).describe(),
		"close to the target")

## The negative half, and the one that catches the next movement op added
## without a sentence.
func test_every_movement_op_is_describable_and_editable() -> void:
	for op in BlockCatalog.MOVEMENT_OPS:
		var block := BlockCatalog.movement(op)
		assert_true(block.describe() != "",
			"'%s' has no sentence, so it renders as nothing in the plan editor" % op)
		for property in block.operands():
			assert_true(String(property["hint_string"]).split(",").size() >= 3,
				"the editor cannot bound '%s' without an export range" % property["name"])

## Issue 640: the editor reads the operand off `get_property_list()`, so the
## control and the field the evaluator reads cannot be two different things.
func test_the_operand_is_the_field_the_interpreter_reads() -> void:
	var block := BlockCatalog.movement(&"keep_distance")
	var operands := block.operands()
	assert_eq(operands.size(), 1)
	assert_eq(operands[0]["name"], &"range_units")
	assert_true(float(String(operands[0]["hint_string"]).split(",")[2]) > 0.0,
		"a step of 0 makes the SpinBox unusable")

## Issue 261's trap, one screen over: a SpinBox step that cannot land on an
## authored value draws a number the plan does not hold.
func test_the_step_can_express_the_default() -> void:
	var block := BlockCatalog.movement(&"keep_distance")
	var step := float(String(block.operands()[0]["hint_string"]).split(",")[2])
	var default_value: float = block.get(&"range_units")
	assert_almost_eq(fmod(default_value, step), 0.0, 0.0001,
		"the default %0.1f does not sit on the step of %0.1f" % [default_value, step])
