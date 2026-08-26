extends PlanBlock
class_name ConditionBlock

## A plan's trigger. Holds or does not; never takes time and never moves anyone.

func holds(_state: CombatState, _unit: CombatUnit) -> bool:
	return false
