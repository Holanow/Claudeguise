extends UseActionBlock
class_name UseBestAttackBlock

## The cheapest attack on whichever side of the melee/ranged split matches how
## far away the target is standing.

func resolve(state: CombatState, unit: CombatUnit, target_id: int) -> ActionDef:
	return DefaultPlan.best_attack(state, unit, state.unit(target_id))

func describe() -> String:
	return "use my best attack for this distance"
