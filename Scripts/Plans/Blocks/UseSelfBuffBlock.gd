extends UseActionBlock
class_name UseSelfBuffBlock

## The first action the unit carries that it casts on itself and that is not a
## heal, a sustain or a summon.

func resolve(state: CombatState, unit: CombatUnit, _target_id: int) -> StringName:
	var buff := DefaultPlan.self_buff(state, unit)
	return buff.id if buff != null else &""

func describe() -> String:
	return "use my first self-buff"
