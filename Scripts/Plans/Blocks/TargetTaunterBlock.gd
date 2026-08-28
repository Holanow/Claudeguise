extends TargetingBlock
class_name TargetTaunterBlock

## The nearest enemy carrying TAUNTING whose own radius reaches this unit.
## Selection only: the unit still approaches and commits as it would against
## anyone else.

func pick(state: CombatState, unit: CombatUnit) -> int:
	var t := taunter(state, unit)
	return t.id if t != null else -1

## Shared with `TargetPileOnBlock`, which must not roll its dice while a taunt
## outranks it.
static func taunter(state: CombatState, unit: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for e in PlanInterpreter.attackable(state, unit):
		if not e.has_status(CG.Status.TAUNTING):
			continue
		var d := unit.position.distance_to(e.position)
		if d > e.taunt_radius:
			continue
		if d < best_dist:
			best_dist = d
			best = e
	return best

func describe() -> String:
	return "whoever is taunting me"
