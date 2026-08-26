extends TargetingBlock
class_name TargetFocusedEnemyBlock

## Issue 588: so a written plan can aim at the player's click deliberately,
## rather than having its own targeting silently overruled.

func pick(state: CombatState, unit: CombatUnit) -> int:
	var focused := DefaultBehavior.player_focus(state, state.living(PlanInterpreter.enemy_team(unit.team)))
	return focused.id if focused != null else -1

func describe() -> String:
	return "the enemy the player focused"
