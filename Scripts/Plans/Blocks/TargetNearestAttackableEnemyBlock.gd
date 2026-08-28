extends TargetingBlock
class_name TargetNearestAttackableEnemyBlock

## The nearest enemy this unit is allowed to attack. Issue 93: a unit whose
## whole arsenal is marked-only may only aim at a marked enemy, so "nearest"
## and "nearest legal" are different questions and this asks the second.

func pick(state: CombatState, unit: CombatUnit) -> int:
	var best: CombatUnit = null
	var best_dist := INF
	for e in PlanInterpreter.attackable(state, unit):
		var d := unit.position.distance_to(e.position)
		if d < best_dist:
			best_dist = d
			best = e
	return best.id if best != null else -1

func describe() -> String:
	return "the nearest enemy I am allowed to attack"
