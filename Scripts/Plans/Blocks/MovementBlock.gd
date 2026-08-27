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

## The same question as `run`, asked by the default rows: they carry their
## target rather than reading `unit.focus_id`, and their intents belong to no
## plan the player wrote.
func aim(_state: CombatState, _unit: CombatUnit, _target_id: int, _action_id: StringName) -> Intent:
	return null

## Fire, once the walking is done. A default row has no plan to attribute the
## intent to and carries its own target; an authored row goes through the gate
## every other action in a plan goes through.
static func act_here(state: CombatState, unit: CombatUnit, target_id: int, action_id: StringName, plan) -> Intent:
	if plan == null:
		return Intent.use_action(action_id, target_id)
	return act_or_idle(state, unit, plan, action_id)
