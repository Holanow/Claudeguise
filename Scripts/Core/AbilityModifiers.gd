extends RefCounted
class_name AbilityModifiers

## Issue 632: reads a unit's equipped modifiers and answers what an action
## becomes for THAT unit.
##
## It returns values and never a modified `ActionDef`. An `ActionDef` is a
## shared resource -- one `.tres` loaded once and handed to every unit that
## uses it -- so writing a caster's bonus onto it would corrupt the action
## process-wide for everyone, with nothing going red.

## Every modifier the unit is carrying. Enemies have no pawn and no equipment,
## so this is empty for them and every query below is the unmodified answer.
static func of(unit: CombatUnit) -> Array[AbilityModifier]:
	var out: Array[AbilityModifier] = []
	if unit == null or unit.pawn == null:
		return out
	for item in unit.pawn.equipment():
		for m in item.modifiers:
			if m != null:
				out.append(m)
	return out

static func extra_targets(unit: CombatUnit, action: ActionDef) -> int:
	var n := 0
	for m in of(unit):
		if m.matches(action):
			n += m.target_count_bonus
	return n

static func power_multiplier(unit: CombatUnit, action: ActionDef) -> float:
	var f := 1.0
	for m in of(unit):
		if m.matches(action):
			f *= m.power_multiplier
	return f

## Statuses an item adds to a landed hit that the action itself never applies.
static func added_statuses(unit: CombatUnit, action: ActionDef) -> Array:
	var out: Array = []
	for m in of(unit):
		if m.adds_status_enabled and m.matches(action):
			out.append({"status": m.adds_status, "ticks": m.adds_status_ticks})
	return out
