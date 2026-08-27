extends PlanBlock
class_name EngageBlock

## Close to the target's own commit distance, then attack with whichever of my
## attacks suits that distance. The commit fractions exist because CombatSim
## checks range when a hit LANDS, not when it commits, so firing at the very
## edge is a guaranteed whiff against anything that flees during the wind-up.

func run(state: CombatState, unit: CombatUnit, plan: Plan, target: CombatUnit) -> Intent:
	if target == null:
		return Intent.idle(plan.id)
	var attack := DefaultBehavior.attack_for(state, unit, target)
	if attack == null:
		return Intent.idle(plan.id)
	var dist := unit.position.distance_to(target.position)
	var blocked: bool = attack.requires_line_of_sight \
		and state.grid.sight_blocked(unit.position, target.position)

	## A unit that cannot move never walks anywhere: it fires or it holds.
	if unit.move_speed <= 0.0:
		if dist > attack.range_units or blocked:
			return Intent.idle(plan.id)
		return Intent.use_action(attack.id, target.id, plan.id)

	if attack.range_units > DefaultBehavior.MELEE_RANGE_THRESHOLD:
		if blocked:
			return Intent.move_to(target.position, plan.id)
		if dist > attack.range_units * DefaultBehavior.RANGED_COMMIT_FRACTION:
			return Intent.move_to(target.position, plan.id)
		return Intent.use_action(attack.id, target.id, plan.id)

	if dist > attack.range_units * DefaultBehavior.MELEE_COMMIT_FRACTION:
		return Intent.move_to(target.position, plan.id)
	return Intent.use_action(attack.id, target.id, plan.id)

## Reads off the unit, because the fallback belongs to every unit and they own
## different attacks. Null unit is the plan editor asking before a fight.
func describe_for(unit: CombatUnit) -> String:
	return describe()

func describe() -> String:
	return "close to attacking range, then attack"
