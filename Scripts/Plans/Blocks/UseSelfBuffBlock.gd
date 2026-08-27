extends PlanBlock
class_name UseSelfBuffBlock

## The first self-targeted buff this unit could usefully cast. Derived rather
## than named: the fallback belongs to every unit, and they own different ones.

func action_for(state: CombatState, unit: CombatUnit) -> ActionDef:
	return DefaultBehavior.self_buff_for(state, unit,
		DefaultBehavior.legal_enemies(state, unit))

func describe() -> String:
	return "steady myself"
