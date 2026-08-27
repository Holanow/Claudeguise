extends ConditionBlock
class_name SelfOnHarmfulGroundBlock

## Issue 384: reads `CombatSim.standing_harms`, the one place "does this ground
## cost me anything" is answered.

func holds(state: CombatState, unit: CombatUnit) -> bool:
	return CombatSim.standing_harms(state, unit.position)

func describe() -> String:
	return "standing on harmful ground"
