extends "res://Tests/TestCase.gd"


## Issue 406. "With no rows the Priest and the Geysermancer are the same class"
## is checkable, and the tick-ratio proxy in `test_content_encounter.gd` cannot
## check it: two parties that both lose every fight look alike to it whatever
## they cast. These read what the pawns actually did.

const SEEDS := 8
func test_the_two_casters_split_the_way_the_player_asked_them_to() -> void:
	var priest := PawnFactory.make_starter_pawn(&"priest", &"p", "Priest")
	var geyser := PawnFactory.make_starter_pawn(&"geysermancer", &"g", "Geysermancer")
	var p_hp := priest.max_hp()
	var g_hp := geyser.max_hp()
	print("556: priest hp %d resource %d move %.2f power %.2f | geysermancer hp %d resource %d move %.2f power %.2f" % [
		p_hp, priest.max_resource(), priest.move_speed(), priest.attack_power(CG.DamageType.DIVINE),
		g_hp, geyser.max_resource(), geyser.move_speed(), geyser.attack_power(CG.DamageType.WATER)])
	assert_true(priest.max_resource() > geyser.max_resource(),
		"the Priest's pool is not the larger one")
	assert_true(geyser.attack_power(CG.DamageType.WATER) > priest.attack_power(CG.DamageType.DIVINE),
		"the Geysermancer does not hit harder")
	assert_true(geyser.move_speed() > priest.move_speed(),
		"the Geysermancer is not the faster one")
	assert_true(g_hp < p_hp, "the Priest does not have more health")
func test_a_dps_library_leads_with_a_damaging_row() -> void:
	for class_id in [&"geysermancer", &"priest"]:
		var library := PresetPlans.for_class(class_id)
		assert_false(library.is_empty(), "%s has no library" % class_id)
		var first: ActionDef = ActionLibrary.get_action(_action_of(library[0]))
		assert_not_null(first, "%s's first library row names no action" % class_id)
		var wants_damage := ClassLibrary.get_class_def(class_id).role_primary == CG.Role.DPS
		assert_eq(first.power_scale > 0.0 and not first.heals, wants_damage,
			"%s leads with %s" % [class_id, first.id])


func _action_of(plan: Plan) -> StringName:
	for b in plan.blocks:
		if b is UseActionBlock:
			var a: ActionDef = (b as UseActionBlock).action
			return a.id if a != null else &""
	return &""
