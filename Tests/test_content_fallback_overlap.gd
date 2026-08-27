extends "res://Tests/TestCase.gd"


## Issue 433: whether a class's top library row changes the fight at all. A row
## that restates a hidden default reads to the player as an edit that did
## nothing, which breaks the author-watch-adjust loop on the first turn.


const SEEDS := 8
func test_both_heal_rows_fire_above_the_fallbacks_own_threshold() -> void:
	for fraction in [PresetPlans.HEAL_ABOVE_FALLBACK, PresetPlans.SECOND_WIND_ABOVE_FALLBACK]:
		assert_true(fraction > DefaultBehavior.HEAL_THRESHOLD_FRACTION,
			"%f is at or under the fallback's %f, so the row restates it" % [
				fraction, DefaultBehavior.HEAL_THRESHOLD_FRACTION])


## The Warrior's Taunt row asks for the Taunt's own reach, so it cannot order a
## shout that reaches nobody. Read off the registry rather than retyped.
func test_the_taunt_row_asks_for_the_taunts_own_radius() -> void:
	var top := PresetPlans.for_class(&"warrior")[0]
	assert_true(top.condition is EnemyInRangeBlock, "the Warrior no longer leads with a ranged condition")
	assert_eq((top.condition as EnemyInRangeBlock).range_units, Registry.get_action(&"warrior_taunt").taunt_radius,
		"the Taunt row's range has drifted from warrior_taunt's taunt_radius")
func _action_of(plan: Plan) -> StringName:
	for b in plan.blocks:
		if b is UseActionBlock:
			var a: ActionDef = (b as UseActionBlock).action
			return a.id if a != null else &""
	return &""
