extends ConditionBlock
class_name EnemyHasStatusBlock

## Any living enemy carrying the named status.
@export var status: CG.Status = CG.Status.SHIELD

func holds(state: CombatState, unit: CombatUnit) -> bool:
	return PlanInterpreter.nearest_enemy_with_status(state, unit, status) != null

func describe() -> String:
	return "an enemy has %s" % PlanInterpreter.status_word(status)
