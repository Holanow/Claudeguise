extends ConditionBlock
class_name AllyNeedsHealBlock

## An ally the pawn can actually put health back into is at or below this share
## of its maximum. "Can heal" is the reach of the pawn's own healing action, so
## a heal with no range asks only about the pawn itself.
@export_range(0.0, 1.0, 0.05) var fraction: float = 0.5

func holds(state: CombatState, unit: CombatUnit) -> bool:
	var neediest := PlanInterpreter.heal_target(state, unit)
	return neediest != null and neediest.hp_fraction() <= fraction

func describe() -> String:
	return "an ally I can heal is at or below %d%% hp" % int(round(fraction * 100.0))
