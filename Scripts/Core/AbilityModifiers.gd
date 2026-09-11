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

## Issue 916: a rolled "% increased damage" affix multiplies here rather than
## through an `AbilityModifier`, so the equip screen names it once.
static func power_multiplier(unit: CombatUnit, action: ActionDef) -> float:
	var f := 1.0
	for m in of(unit):
		if m.matches(action):
			f *= m.power_multiplier
	if unit != null and unit.pawn != null:
		for item in unit.pawn.equipment():
			f *= item.affix_power_multiplier()
	return f

## Issue 918: what the wielder's gear does to this action's wind-up and
## recovery. The Mace is slow, and that is the cost of its weight.
static func action_ticks_multiplier(unit: CombatUnit, action: ActionDef) -> float:
	var f := 1.0
	for m in of(unit):
		if m.matches(action):
			f *= m.action_ticks_multiplier
	return f

## Statuses an item adds to a landed hit that the action itself never applies.
## `chance` is drawn by the caller, from `state.rng`, in this list's order --
## never here, so a query never perturbs the fight it is asked about.
##
## Issue 931: `source` names the piece that added it, so the combat log's proc
## tag reads this list rather than walking the gear a second time.
static func added_statuses(unit: CombatUnit, action: ActionDef) -> Array:
	var out: Array = []
	if unit == null or unit.pawn == null:
		return out
	for item in unit.pawn.equipment():
		for m in item.modifiers:
			if m == null or not m.adds_status_enabled or not m.matches(action):
				continue
			out.append({"status": m.adds_status, "ticks": m.adds_status_ticks,
				"chance": m.adds_status_chance, "source": _modifier_source(item, m)})
		out.append_array(item.affix_added_statuses())
	return out

## An affix names itself the same way, so the two entries read alike.
static func _modifier_source(item: EquipmentDef, m: AbilityModifier) -> String:
	if m.display_name == "":
		return item.display_name
	return "%s: %s" % [item.display_name, m.display_name]
