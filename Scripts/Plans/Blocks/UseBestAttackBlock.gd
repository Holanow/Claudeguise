extends UseActionBlock
class_name UseBestAttackBlock

## The cheapest attack on whichever side of the melee/ranged split matches how
## far away the target is standing.

func resolve(state: CombatState, unit: CombatUnit, target_id: int) -> StringName:
	var attack := DefaultPlan.best_attack(state, unit, state.unit(target_id))
	return attack.id if attack != null else &""

func describe() -> String:
	return "use my best attack for this distance"
