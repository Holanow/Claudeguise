extends UseActionBlock
class_name UseHealBlock

## The unit's healing action, which is the first one it carries that both heals
## and restores something.

func resolve(state: CombatState, unit: CombatUnit, _target_id: int) -> ActionDef:
	return PlanInterpreter.heal_action(state, unit)

func describe() -> String:
	return "use my healing action"
