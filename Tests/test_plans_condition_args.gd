extends "res://Tests/TestCase.gd"


## **Every number a preset plan states must be a number the plan editor can
## draw.** Found by looking at a rendered screen rather than at the data: a
## `SpinBox` snaps whatever value it is handed to its own step, so
## `abomination_grapple_close`'s 45 units drew as **50** beside a chip reading
## "An enemy within 45 units". The plan held 45 the whole time and only the
## screen lied, which is the worst version of it -- nothing in the simulation is
## wrong, so nothing could ever go red, and the player is reading a number the
## pawn is not using.

func test_every_authored_condition_argument_is_drawable_in_the_editor() -> void:
	var checked := 0
	for class_id in Registry.all_class_ids():
		for plan in PresetPlans.for_class(class_id):
			var blocks: Array = [plan.condition]
			for b in plan.blocks:
				blocks.append(b)
			for block in blocks:
				if block == null or block.kind != PlanBlock.Kind.CONDITION:
					continue
				var shape: Dictionary = PlanInterpreter.CONDITION_ARG_SHAPE.get(block.op, {"kind": "none"})
				var kind: String = shape.get("kind", "none")
				if kind == "none" or kind == "status":
					continue
				var key: String = shape["key"]
				assert_true(
					block.args.has(key),
					"%s/%s states op %s with no '%s' argument" % [class_id, plan.id, block.op, key]
				)
				var raw := float(block.args[key])
				# The editor's own units. "fraction" is edited as whole percent.
				var shown := raw * 100.0 if kind == "fraction" else raw
				var step := 5.0 if kind == "fraction" else float(shape["step"])
				var lo := 0.0 if kind == "fraction" else float(shape["min"])
				var hi := 100.0 if kind == "fraction" else float(shape["max"])
				checked += 1
				assert_true(
					shown >= lo and shown <= hi,
					"%s/%s: %s = %s is outside the editor's %s..%s" % [class_id, plan.id, key, shown, lo, hi]
				)
				assert_almost_eq(
					shown, snappedf(shown, step), 0.0001,
					"%s/%s: %s = %s is not on the editor's step of %s, so the SpinBox draws %s instead" % [
						class_id, plan.id, key, shown, step, snappedf(shown, step)
					]
				)
	# Non-vacuity: sixteen preset plans carry a numeric condition today, and a
	# walk that finds none must not read as a pass.
	assert_true(checked >= 10, "only %d condition arguments were checked" % checked)
