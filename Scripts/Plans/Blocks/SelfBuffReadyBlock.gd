extends ConditionBlock
class_name SelfBuffReadyBlock

## Issue 150: the fight is close enough that a self-buff is worth a cast.
## "Close enough" is the buff's own taunt radius, or the unit's longest attack.

func holds(state: CombatState, unit: CombatUnit) -> bool:
	return DefaultBehavior.self_buff_for(state, unit,
		DefaultBehavior.legal_enemies(state, unit)) != null

func describe() -> String:
	return "the fight is within my reach"
