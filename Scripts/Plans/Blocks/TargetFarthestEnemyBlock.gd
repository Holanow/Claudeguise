extends TargetingBlock
class_name TargetFarthestEnemyBlock

func pick(state: CombatState, unit: CombatUnit) -> int:
	var f := PlanInterpreter.farthest(state, unit, PlanInterpreter.enemy_team(unit.team))
	return f.id if f != null else -1

func describe() -> String:
	return "the farthest enemy"
