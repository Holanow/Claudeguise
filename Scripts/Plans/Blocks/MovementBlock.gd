extends PlanBlock
class_name MovementBlock

## Where the pawn stands, which is issue 97's whole point: before it, movement
## was `DefaultBehavior`'s and no plan could say anything about it.

## The Intent for the whole plan, or null to step aside to the next row.
func run(_state: CombatState, _unit: CombatUnit, _plan: Plan, _action_id: StringName) -> Intent:
	return null

## Every movement op ends the same way once the pawn has arrived.
static func act_or_idle(state: CombatState, unit: CombatUnit, plan: Plan, action_id: StringName) -> Intent:
	if action_id == &"" or not PlanInterpreter.action_can_fire(state, unit, action_id):
		return Intent.idle(plan.id)
	return Intent.use_action(action_id, PlanInterpreter.action_target_id(unit, action_id), plan.id)
