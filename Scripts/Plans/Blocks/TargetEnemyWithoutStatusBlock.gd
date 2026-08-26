extends TargetingBlock
class_name TargetEnemyWithoutStatusBlock

@export var status: CG.Status = CG.Status.SHIELD

func pick(state: CombatState, unit: CombatUnit) -> int:
	var clean := PlanInterpreter.nearest_enemy_without_status(state, unit, status)
	return clean.id if clean != null else -1

func describe() -> String:
	return "the nearest enemy without %s" % PlanInterpreter.status_word(status)
