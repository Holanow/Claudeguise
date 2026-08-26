extends "res://Tests/TestCase.gd"


## **Every number a preset plan states must be a number the plan editor can
## draw.** Found by looking at a rendered screen rather than at the data: a
## `SpinBox` snaps whatever value it is handed to its own step, so
## `abomination_grapple_close`'s 45 units drew as **50** beside a chip reading
## "An enemy within 45 units". The plan held 45 the whole time and only the
## screen lied, which is the worst version of it -- nothing in the simulation is
## wrong, so nothing could ever go red, and the player is reading a number the
## pawn is not using.

## Issue 640: the bounds are read off the block's own `@export_range`, which is
## what `InspectPanel._operand_editor` reads. There is no shape table left to
## disagree with the field.
func test_every_authored_condition_argument_is_drawable_in_the_editor() -> void:
	var checked := 0
	for class_id in Registry.all_class_ids():
		for plan in PresetPlans.for_class(class_id):
			var blocks: Array = [plan.condition]
			for b in plan.blocks:
				blocks.append(b)
			for block in blocks:
				if not (block is ConditionBlock):
					continue
				for property in block.operands():
					if property["type"] == TYPE_INT and property["hint"] == PROPERTY_HINT_ENUM:
						continue
					var parts := String(property["hint_string"]).split(",")
					assert_true(parts.size() >= 3,
						"%s/%s: %s has no export range, so the editor cannot bound it" % [
							class_id, plan.id, property["name"]])
					# The editor's own units. A share is edited as whole percent.
					var scale := 100.0 if float(parts[1]) == 1.0 else 1.0
					var lo := float(parts[0]) * scale
					var hi := float(parts[1]) * scale
					var step := float(parts[2]) * scale
					var shown := float(block.get(property["name"])) * scale
					checked += 1
					assert_true(
						shown >= lo and shown <= hi,
						"%s/%s: %s = %s is outside the editor's %s..%s" % [
							class_id, plan.id, property["name"], shown, lo, hi]
					)
					assert_almost_eq(
						shown, snappedf(shown, step), 0.0001,
						"%s/%s: %s = %s is not on the editor's step of %s, so the SpinBox draws %s instead" % [
							class_id, plan.id, property["name"], shown, step, snappedf(shown, step)
						]
					)
	# Non-vacuity: sixteen preset plans carry a numeric condition today, and a
	# walk that finds none must not read as a pass.
	assert_true(checked >= 10, "only %d condition arguments were checked" % checked)
