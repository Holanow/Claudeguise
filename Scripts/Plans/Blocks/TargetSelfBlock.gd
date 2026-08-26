extends TargetingBlock
class_name TargetSelfBlock

func pick(_state: CombatState, unit: CombatUnit) -> int:
	return unit.id

func describe() -> String:
	return "self"
