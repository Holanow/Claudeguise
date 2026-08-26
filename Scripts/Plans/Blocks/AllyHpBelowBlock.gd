extends ConditionBlock
class_name AllyHpBelowBlock

## Any living ally under this share of its maximum health, the pawn included.
@export_range(0.0, 1.0, 0.05) var fraction: float = 0.5

func holds(state: CombatState, unit: CombatUnit) -> bool:
	for ally in state.living(unit.team):
		if ally.hp_fraction() < fraction:
			return true
	return false

func describe() -> String:
	return "an ally's hp below %d%%" % int(round(fraction * 100.0))
