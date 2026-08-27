extends PlanBlock
class_name UseActionBlock

## The only block that takes time. Issue 658: it holds the action itself, not
## its name. `action` is not an operand the generic editor builds a spinner
## for -- the plan editor offers the pawn's own actions.
@export var action: ActionDef

func describe() -> String:
	return "use %s" % (action.display_name if action != null else "nothing")

## Which action this block fires, asked once the plan's targeting has settled.
## A derived block answers with something it works out per tick; a plain one
## answers with the action the player picked.
func resolve(_state: CombatState, _unit: CombatUnit, _target_id: int) -> ActionDef:
	return action
