extends UseActionBlock
class_name UseHealBlock

## The unit's healing action, which is the first one it carries that both heals
## and restores something.

func resolve(state: CombatState, unit: CombatUnit, _target_id: int) -> StringName:
	var heal := DefaultPlan.heal_action(state, unit)
	return heal.id if heal != null else &""

func describe() -> String:
	return "use my healing action"
