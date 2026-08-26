extends ConditionBlock
class_name SelfNotInCoverBlock

## The strict complement of `SelfInCoverBlock`, so the two-row plan "not in
## cover -> take cover / in cover -> act" starts from the right half.

func holds(state: CombatState, unit: CombatUnit) -> bool:
	return not PlanInterpreter.unit_in_cover(state, unit)

func describe() -> String:
	return "not in cover from the target"
