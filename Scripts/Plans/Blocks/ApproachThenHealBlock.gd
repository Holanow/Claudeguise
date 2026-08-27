extends PlanBlock
class_name ApproachThenHealBlock

## Walk to the ally if the heal cannot reach, then cast. `KeepDistanceBlock`
## is not this: it holds a band with a harm check and a kite anchor, and this
## walks straight at the target the way the fallback always has.

func run(state: CombatState, unit: CombatUnit, plan: Plan, ally: CombatUnit) -> Intent:
	var heal := DefaultBehavior.heal_action_for(state, unit)
	if heal == null or ally == null:
		return null
	if unit.position.distance_to(ally.position) <= heal.range_units:
		return Intent.use_action(heal.id, ally.id, plan.id)
	return Intent.move_to(ally.position, plan.id)

func describe() -> String:
	return "move into range, then heal them"
