extends UseActionBlock
class_name UseBestAttackBlock

## The cheapest attack on whichever side of the melee/ranged split matches how
## far away the target is standing. Issue 719: moved here from `DefaultPlan`,
## whose own fallback row no longer runs a cost search at all -- this block is
## its only remaining caller, for a plan the player authors.

func resolve(state: CombatState, unit: CombatUnit, target_id: int) -> ActionDef:
	return best_attack(state, unit, state.unit(target_id))

## Issue 62: the attack whose own shape matches the target's current distance.
static func best_attack(state: CombatState, unit: CombatUnit, target: CombatUnit) -> ActionDef:
	if target == null:
		return null
	var actions := PlanInterpreter.candidates(state, unit)
	var melee := side_attack(actions, false)
	var ranged := side_attack(actions, true)
	if melee == null:
		return ranged
	if ranged == null:
		return melee
	if unit.gap(target) <= melee.range_units * DefaultPlan.MELEE_COMMIT_FRACTION:
		return melee
	return ranged

## The cheapest attack on one side of the melee/ranged split, ties by list
## order. Null when the unit owns none on that side.
static func side_attack(actions: Array[ActionDef], want_ranged: bool) -> ActionDef:
	var best: ActionDef = null
	for a in PlanInterpreter.attacks(actions):
		if (a.range_units > DefaultPlan.MELEE_RANGE_THRESHOLD) != want_ranged:
			continue
		if best == null or a.resource_cost < best.resource_cost:
			best = a
	return best

func describe() -> String:
	return "use my best attack for this distance"
