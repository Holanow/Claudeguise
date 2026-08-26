extends ConditionBlock
class_name SelfResourceBelowBlock

## The complement of `SelfResourceAtLeastBlock`, so a Channel row can say "only
## when there is room for what it restores".
@export_range(0, 999, 1) var amount: int = 0

func holds(_state: CombatState, unit: CombatUnit) -> bool:
	return unit.resource < amount

func describe() -> String:
	return "self resource below %d" % amount
