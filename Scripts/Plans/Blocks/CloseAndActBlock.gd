extends MovementBlock
class_name CloseAndActBlock

## Close on the target until the action is comfortably in range, then use it.
## Range is checked when a hit lands rather than when it commits, so firing
## right at the edge is a guaranteed whiff against anything that flees.
@export_range(0.0, 1.0, 0.05) var melee_fraction: float = 0.5
@export_range(0.0, 1.0, 0.05) var ranged_fraction: float = 0.85

func run(state: CombatState, unit: CombatUnit, plan: Plan, action_id: StringName) -> Intent:
	return _walk(state, unit, unit.focus_id, action_id, plan)

func aim(state: CombatState, unit: CombatUnit, target_id: int, action_id: StringName) -> Intent:
	return _walk(state, unit, target_id, action_id, null)

func _walk(state: CombatState, unit: CombatUnit, target_id: int, action_id: StringName, plan) -> Intent:
	var target := state.unit(target_id)
	var action: ActionDef = Registry.get_action(action_id)
	if target == null or not target.alive or action == null:
		return null
	var dist := unit.position.distance_to(target.position)
	var blocked := action.requires_line_of_sight \
		and Terrain.line_is_blocked(state.terrain, unit.position, target.position)

	## A unit that cannot walk has no approach to make: it fires or it waits.
	if unit.move_speed <= 0.0:
		if dist > action.range_units or blocked:
			return Intent.idle(&"" if plan == null else plan.id)
		return act_here(state, unit, target_id, action_id, plan)

	var fraction := ranged_fraction if action.range_units > DefaultPlan.MELEE_RANGE_THRESHOLD else melee_fraction
	if blocked and action.range_units > DefaultPlan.MELEE_RANGE_THRESHOLD:
		return Intent.move_to(target.position, &"" if plan == null else plan.id)
	if dist > action.range_units * fraction:
		return Intent.move_to(target.position, &"" if plan == null else plan.id)
	return act_here(state, unit, target_id, action_id, plan)

func describe() -> String:
	return "close to within %d%% of a melee action's range, or %d%% of a ranged one's, then act" % [
		int(round(melee_fraction * 100.0)), int(round(ranged_fraction * 100.0))]
