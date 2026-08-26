extends ConditionBlock
class_name AlwaysBlock

## The row fires whenever the pawn is free. A plan with a null condition means
## the same thing, which is why `condition_holds` treats the two alike.

func holds(_state: CombatState, _unit: CombatUnit) -> bool:
	return true

func describe() -> String:
	return "always"
