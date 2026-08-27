extends UseActionBlock
class_name UseSelfBuffBlock

## The first action the unit carries that it casts on itself and that is not a
## heal, a sustain or a summon.

func resolve(state: CombatState, unit: CombatUnit, _target_id: int) -> ActionDef:
	return DefaultPlan.self_buff(state, unit)

func describe() -> String:
	return "use my first self-buff"
