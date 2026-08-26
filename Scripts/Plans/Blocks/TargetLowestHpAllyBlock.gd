extends TargetingBlock
class_name TargetLowestHpAllyBlock

func pick(state: CombatState, unit: CombatUnit) -> int:
	var a := PlanInterpreter.lowest_hp_fraction(state.living(unit.team))
	return a.id if a != null else -1

func describe() -> String:
	return "the ally with the lowest hp"
