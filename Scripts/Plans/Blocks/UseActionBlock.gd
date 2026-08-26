extends PlanBlock
class_name UseActionBlock

## The only block that takes time. `action_id` is not an operand the generic
## editor builds a spinner for: the plan editor offers the pawn's own actions.
@export var action_id: StringName = &""

func describe() -> String:
	var action := Registry.get_action(action_id)
	return "use %s" % (action.display_name if action != null else String(action_id))
