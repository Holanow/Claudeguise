extends ConditionBlock
class_name EnemyInRangeBlock

## The nearest enemy within this many world units.
@export_range(0.0, 1000.0, 5.0) var range_units: float = 100.0

func holds(state: CombatState, unit: CombatUnit) -> bool:
	var nearest := PlanInterpreter.nearest(state, unit, PlanInterpreter.enemy_team(unit.team))
	if nearest == null:
		return false
	return unit.gap(nearest) <= range_units

func describe() -> String:
	return "an enemy within %d units" % int(range_units)
