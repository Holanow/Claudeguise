extends MovementBlock
class_name MoveIntoCoverBlock

## Issue 316: put something solid between this pawn and the enemy the plan is
## aimed at, then act from there. Cover from the FOCUS, not from everyone.

func run(state: CombatState, unit: CombatUnit, plan: Plan, action: ActionDef) -> Intent:
	var threat := state.unit(unit.focus_id)
	if threat == null or not threat.alive:
		return null
	## Cover from the target is also cover from your own shot: this game's cover
	## is binary line of sight, with no peeking out. The pairing has no
	## satisfying position, so the row steps aside for the next one.
	if action != null and action.requires_line_of_sight:
		return null
	if PlanInterpreter.in_cover_from(state, unit, unit.position, threat):
		return act_or_idle(state, unit, plan, action, unit.focus_id)
	var spot = PlanInterpreter.cover_spot(state, unit, threat)
	if spot == null:
		return null
	return Intent.move_to(spot, plan.id)

func describe() -> String:
	return "move into cover from the target"
