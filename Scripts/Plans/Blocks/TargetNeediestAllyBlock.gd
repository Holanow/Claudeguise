extends TargetingBlock
class_name TargetNeediestAllyBlock

## The ally the fallback's own heal would go to, which is not always the lowest
## in the party: a heal with no range only reaches the caster.

func pick(state: CombatState, unit: CombatUnit) -> int:
	var ally := DefaultBehavior.neediest_heal_target(state, unit)
	return ally.id if ally != null else -1

func describe() -> String:
	return "that ally"
