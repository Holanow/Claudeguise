extends PlanBlock
class_name UseActionBlock

## The only block that takes time. `action_id` is not an operand the generic
## editor builds a spinner for: the plan editor offers the pawn's own actions.
@export var action_id: StringName = &""

func describe() -> String:
	var action := Registry.get_action(action_id)
	return "use %s" % (action.display_name if action != null else String(action_id))

## Which action this block fires, asked once the plan's targeting has settled.
## A derived block answers with something it works out per tick; a plain one
## answers with the id the player picked.
func resolve(_state: CombatState, _unit: CombatUnit, _target_id: int) -> StringName:
	return action_id
