extends ConditionBlock
class_name SelfResourceAtLeastBlock

## A flat amount of the pawn's own resource.
@export_range(0, 999, 1) var amount: int = 0

func holds(_state: CombatState, unit: CombatUnit) -> bool:
	return unit.resource >= amount

func describe() -> String:
	return "self resource at least %d" % amount
