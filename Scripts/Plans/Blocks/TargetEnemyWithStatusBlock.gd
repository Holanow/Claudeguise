extends TargetingBlock
class_name TargetEnemyWithStatusBlock

@export var status: CG.Status = CG.Status.SHIELD

func pick(state: CombatState, unit: CombatUnit) -> int:
	var marked := PlanInterpreter.nearest_enemy_with_status(state, unit, status)
	return marked.id if marked != null else -1

func describe() -> String:
	return "the nearest enemy with %s" % PlanInterpreter.status_word(status)
