extends TargetingBlock
class_name TargetHealTargetBlock

## The ally with the least health left of those the pawn's own heal can reach.

func pick(state: CombatState, unit: CombatUnit) -> int:
	var ally := DefaultPlan.heal_target(state, unit)
	return ally.id if ally != null else -1

func describe() -> String:
	return "the ally who most needs my heal"
