extends TargetingBlock
class_name TargetNearestEnemyBlock

func pick(state: CombatState, unit: CombatUnit) -> int:
	var n := PlanInterpreter.nearest(state, unit, PlanInterpreter.enemy_team(unit.team))
	return n.id if n != null else -1

func describe() -> String:
	return "the nearest enemy"
