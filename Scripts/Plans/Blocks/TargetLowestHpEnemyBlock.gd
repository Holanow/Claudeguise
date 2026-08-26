extends TargetingBlock
class_name TargetLowestHpEnemyBlock

func pick(state: CombatState, unit: CombatUnit) -> int:
	var e := PlanInterpreter.lowest_hp_fraction(state.living(PlanInterpreter.enemy_team(unit.team)))
	return e.id if e != null else -1

func describe() -> String:
	return "the enemy with the lowest hp"
