extends ConditionBlock
class_name EnemyLacksStatusBlock

## Issue 206: the complement of `EnemyHasStatusBlock`, asked through the same
## helper so the two cannot disagree about which enemy qualifies.
@export var status: CG.Status = CG.Status.SHIELD

func holds(state: CombatState, unit: CombatUnit) -> bool:
	return PlanInterpreter.nearest_enemy_without_status(state, unit, status) != null

func describe() -> String:
	return "an enemy has no %s" % PlanInterpreter.status_word(status)
