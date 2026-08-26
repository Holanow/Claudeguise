extends TargetingBlock
class_name TargetAfflictedAllyBlock

func pick(state: CombatState, unit: CombatUnit) -> int:
	var afflicted := PlanInterpreter.nearest_afflicted_ally(state, unit)
	return afflicted.id if afflicted != null else -1

func describe() -> String:
	return "the nearest ally with a harmful status"
