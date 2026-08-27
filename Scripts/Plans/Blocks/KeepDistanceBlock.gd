extends MovementBlock
class_name KeepDistanceBlock

## Hold this many world units from the focus, on ground that does not harm.
@export_range(0.0, 1000.0, 5.0) var range_units: float = 120.0

func run(state: CombatState, unit: CombatUnit, plan: Plan, action_id: StringName) -> Intent:
	var target := state.unit(unit.focus_id)
	if target == null or not target.alive:
		return null

	var dist := unit.gap(target)
	var away := unit.position - target.position
	if away.length() < 0.0001:
		away = Vector2(1.0, 0.0)

	## Standing on harm is not standing at the requested distance: the row
	## promises ground that does not harm, so the band alone cannot mean arrived.
	var arrived := absf(dist - range_units) <= PlanInterpreter.KEEP_DISTANCE_BAND \
		and not CombatSim.standing_harms(state, unit.position)
	if not arrived:
		## `kite_anchor` measures from the target's centre, so the two bodies go
		## back in: an anchor the row would then judge out of band is a spot the
		## unit walks to and immediately leaves again.
		var wanted := range_units + unit.radius + target.radius
		var anchor = PlanInterpreter.kite_anchor(state, unit, target.position, away.normalized(), wanted)
		if anchor == null:
			return null
		return Intent.move_to(anchor, plan.id)

	return act_or_idle(state, unit, plan, action_id)

func describe() -> String:
	var wanted := int(range_units)
	if wanted <= 0:
		return "close to the target"
	return "hold %d units from the target, on ground that does not harm" % wanted
