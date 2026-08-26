extends PlanBlock
class_name TargetingBlock

## Picks who the plan is aimed at. Returns a unit id, or -1 to leave the pawn's
## focus where it already was.

func pick(_state: CombatState, _unit: CombatUnit) -> int:
	return -1
