extends ConditionBlock
class_name AllyHasHarmfulStatusBlock

## Any living ally carrying a status `CG.is_harmful` classifies as harmful.

func holds(state: CombatState, unit: CombatUnit) -> bool:
	return PlanInterpreter.nearest_afflicted_ally(state, unit) != null

func describe() -> String:
	return "an ally has a harmful status"
