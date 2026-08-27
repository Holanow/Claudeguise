extends ConditionBlock
class_name AllyNeedsHealBlock

## The fallback's heal trigger. Not `AllyHpBelowBlock`: that asks about any
## living ally, and this asks about the allies THIS unit's own heal can reach --
## a heal with no range reaches only the caster (issue 99).

func holds(state: CombatState, unit: CombatUnit) -> bool:
	return DefaultBehavior.neediest_heal_target(state, unit) != null

func describe() -> String:
	return "an ally I can heal is at or below %d%% hp" % int(round(
		DefaultBehavior.HEAL_THRESHOLD_FRACTION * 100.0))
