extends ConditionBlock
class_name SelfResourceAtLeastFractionBlock

## Issue 488: the same question as a share of the pawn's own ceiling, because 40
## is all of a Warrior's Rage and 39% of a Priest's Mana.
@export_range(0.0, 1.0, 0.05) var fraction: float = 1.0

func holds(_state: CombatState, unit: CombatUnit) -> bool:
	return unit.resource >= int(ceil(float(unit.resource_max) * fraction))

func describe() -> String:
	return "self resource at least %d%%" % int(round(fraction * 100.0))
