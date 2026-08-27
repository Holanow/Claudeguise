extends MovementBlock
class_name LeaveHarmfulGroundBlock

## Issue 420: the only movement op that is not defined relative to a target, and
## it takes no argument because the room, not the pawn, decides what burns.

func run(state: CombatState, unit: CombatUnit, plan: Plan, action: ActionDef) -> Intent:
	if not CombatSim.standing_harms(state, unit.position):
		return act_or_idle(state, unit, plan, action)
	var spot = PlanInterpreter.safe_spot(state, unit)
	if spot == null:
		return null
	return Intent.move_to(spot, plan.id)

func describe() -> String:
	return "move off harmful ground"
