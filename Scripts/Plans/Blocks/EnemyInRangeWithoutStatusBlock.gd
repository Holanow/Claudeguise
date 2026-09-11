extends ConditionBlock
class_name EnemyInRangeWithoutStatusBlock

## Issue 764: `enemy_in_range` and `enemy_lacks_status` in one slot, because a
## row has one condition and the Siege Master's Mark row needs both -- wait for
## something close, and refuse to pay again for a mark already standing.
@export_range(0.0, 1200.0, 5.0) var range_units: float = 100.0
@export var status: CG.Status = CG.Status.MARKED

func holds(state: CombatState, unit: CombatUnit) -> bool:
	var clean := PlanInterpreter.nearest_enemy_without_status(state, unit, status)
	if clean == null:
		return false
	return unit.gap(clean) <= range_units

func describe() -> String:
	return "an enemy within %d units has no %s" % [
		int(range_units), PlanInterpreter.status_word(status)]
