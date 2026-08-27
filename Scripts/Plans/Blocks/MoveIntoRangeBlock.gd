extends MovementBlock
class_name MoveIntoRangeBlock

## Walk to the target until the action reaches, then use it.

func run(state: CombatState, unit: CombatUnit, plan: Plan, action: ActionDef) -> Intent:
	return _walk(state, unit, unit.focus_id, action, plan)

func aim(state: CombatState, unit: CombatUnit, target_id: int, action: ActionDef) -> Intent:
	return _walk(state, unit, target_id, action, null)

func _walk(state: CombatState, unit: CombatUnit, target_id: int, action: ActionDef, plan) -> Intent:
	var target := state.unit(target_id)
	if target == null or not target.alive or action == null:
		return null
	if unit.position.distance_to(target.position) <= action.range_units:
		return act_here(state, unit, target_id, action, plan)
	return Intent.move_to(target.position, &"" if plan == null else plan.id)

func describe() -> String:
	return "move into range, then act"
