extends ConditionBlock
class_name SelfOnSafeGroundBlock

## The strict complement of `SelfOnHarmfulGroundBlock`.

func holds(state: CombatState, unit: CombatUnit) -> bool:
	return not CombatSim.standing_harms(state, unit.position)

func describe() -> String:
	return "standing on safe ground"
