extends TargetingBlock
class_name TargetPileOnBlock

## Join the enemy this unit's allies are already attacking, as often as the
## unit's own `focus_bias` says. A taunt outranks this, so it does not even
## roll while something is taunting.

func pick(state: CombatState, unit: CombatUnit) -> int:
	if TargetTaunterBlock.taunter(state, unit) != null:
		return -1
	var enemy_def: EnemyDef = EnemyLibrary.get_enemy(unit.enemy_id)
	if enemy_def == null or enemy_def.focus_bias <= 0.0:
		return -1
	var pile := _most_focused(state, unit)
	if pile == null:
		return -1
	return pile.id if state.rng.randf() < enemy_def.focus_bias else -1

## The candidate the most of this unit's living allies currently have as their
## focus_id, read from the field CombatSim sets when an action resolves.
static func _most_focused(state: CombatState, unit: CombatUnit) -> CombatUnit:
	var counts := {}
	for ally in state.living(unit.team):
		if ally.focus_id != -1:
			counts[ally.focus_id] = int(counts.get(ally.focus_id, 0)) + 1
	var best: CombatUnit = null
	var best_count := 0
	for c in DefaultPlan.attackable(state, unit):
		var n := int(counts.get(c.id, 0))
		if n > best_count:
			best_count = n
			best = c
	return best

func describe() -> String:
	return "sometimes, the enemy my allies are already attacking"
