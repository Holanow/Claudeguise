extends ConditionBlock
class_name EnemyWithinBuffReachBlock

## The fight is close enough that a self-buff is worth the cast: an enemy stands
## inside the buff's own taunt radius, or inside the longest attack the unit has
## to follow it up with.

func holds(state: CombatState, unit: CombatUnit) -> bool:
	return PlanInterpreter.self_buff(state, unit) != null

func describe() -> String:
	return "an enemy is close enough for my self-buff to matter"
