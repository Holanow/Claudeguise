extends ConditionBlock
class_name SelfInCoverBlock

## Issue 495: cover from the current focus, matching `MoveIntoCoverBlock`, which
## takes cover from the threat the row picked rather than from everyone.

func holds(state: CombatState, unit: CombatUnit) -> bool:
	return PlanInterpreter.unit_in_cover(state, unit)

func describe() -> String:
	return "in cover from the target"
