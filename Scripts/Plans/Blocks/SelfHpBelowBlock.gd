extends ConditionBlock
class_name SelfHpBelowBlock

## The pawn's own health, as a share of its maximum. Stored 0..1; the editor
## shows whole percent because that is what the sentence prints.
@export_range(0.0, 1.0, 0.05) var fraction: float = 0.5

func holds(_state: CombatState, unit: CombatUnit) -> bool:
	return unit.hp_fraction() < fraction

func describe() -> String:
	return "self hp below %d%%" % int(round(fraction * 100.0))
