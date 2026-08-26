extends ConditionBlock
class_name EnemyIsFocusedBlock

## Issue 588: the player has clicked an enemy and it is still alive. Global
## rather than per-unit, because the focus is one thing the party shares.

func holds(state: CombatState, _unit: CombatUnit) -> bool:
	return DefaultBehavior.player_focus(state, state.living(CG.Team.ENEMY)) != null

func describe() -> String:
	return "the player has focused an enemy"
