extends Resource
class_name PlanBlock

## One block inside a plan, and **the subclass is the op**. `ConditionBlock`
## gates the plan, `TargetingBlock` resolves instantly and moves the pawn's
## focus, `UseActionBlock` is the only kind that takes time, `OnceBlock` says
## how long the action repeats, and `MovementBlock` says where the pawn stands.

## The sentence the plan editor prints for this block.
func describe() -> String:
	return ""

## The exported operands this block carries, in declaration order, straight out
## of `get_property_list()`. The editor builds its controls from these, so a
## control cannot describe an argument the evaluator does not read.
func operands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in get_property_list():
		var usage: int = p["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_EDITOR:
			out.append(p)
	return out
