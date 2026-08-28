extends PlanBlock
class_name MovementBlock

## Where the pawn stands, which is issue 97's whole point: before it, movement
## was `DefaultBehavior`'s and no plan could say anything about it.

## The Intent for the whole plan, or null to step aside to the next row.
func run(_state: CombatState, _unit: CombatUnit, _plan: Plan, _action: ActionDef) -> Intent:
	return null

## Every movement op ends the same way once the pawn has arrived.
static func act_or_idle(state: CombatState, unit: CombatUnit, plan: Plan, action: ActionDef, target_id: int) -> Intent:
	if action == null or not PlanInterpreter.action_can_fire(state, unit, action, target_id):
		return Intent.idle(plan.id)
	return Intent.use_action(action.id, PlanInterpreter.action_target_id(unit, action, target_id), plan.id)

## The same question as `run`, asked by the default rows: they carry their
## target rather than reading `unit.focus_id`, and their intents belong to no
## plan the player wrote.
func aim(_state: CombatState, _unit: CombatUnit, _target_id: int, _action: ActionDef) -> Intent:
	return null

## Fire, once the walking is done. Issue 650: a default row (`plan == null`)
## now goes through the same `action_can_fire` gate an authored row does, and
## gets null back rather than an idle intent -- `DefaultPlan.decide` tries its
## next candidate row with the tick still unspent, where an authored plan has
## no next row and idles instead.
static func act_here(state: CombatState, unit: CombatUnit, target_id: int, action: ActionDef, plan) -> Intent:
	if plan == null:
		if not PlanInterpreter.action_can_fire(state, unit, action, target_id):
			return null
		return Intent.use_action(action.id, target_id)
	return act_or_idle(state, unit, plan, action, target_id)
