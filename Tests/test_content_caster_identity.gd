extends "res://Tests/TestCase.gd"


## Issue 406. "With no rows the Priest and the Geysermancer are the same class"
## is checkable, and the tick-ratio proxy in `test_content_encounter.gd` cannot
## check it: two parties that both lose every fight look alike to it whatever
## they cast. These read what the pawns actually did.

const SEEDS := 8

## Every action a party of this class fired, and how often. Read from the
## finished event stream, never from live unit state.
func _casts(class_id: StringName, presets: bool) -> Dictionary:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	var out := {}
	for s in SEEDS:
		var party: Array[PawnData] = []
		for i in 4:
			var id := StringName("%s_%d" % [class_id, i])
			party.append(
				PawnFactory.make_preset_pawn(class_id, id, String(class_id)) if presets
				else PawnFactory.make_starter_pawn(class_id, id, String(class_id))
			)
		var state := CombatSim.build(party, encounter, s)
		CombatSim.run(state)
		for e in state.events:
			if e.kind != CG.EventKind.ACTION_FIRE:
				continue
			var u := state.unit(e.source_id)
			if u != null and u.pawn != null:
				out[e.action_id] = int(out.get(e.action_id, 0)) + 1
	return out


## Issue 556, the player's sentence as four assertions: *"A priest should
## generally have a higher max resource pool and slightly more health, whereas
## a geysermancer should hit harder and move faster"*. Read off `Balance` for
## the real starter pawns, so a statline edit that undoes any clause goes red.
func test_the_two_casters_split_the_way_the_player_asked_them_to() -> void:
	var priest := PawnFactory.make_starter_pawn(&"priest", &"p", "Priest")
	var geyser := PawnFactory.make_starter_pawn(&"geysermancer", &"g", "Geysermancer")
	var p_hp := Balance.max_hp(priest)
	var g_hp := Balance.max_hp(geyser)
	print("556: priest hp %d resource %d move %.2f power %.2f | geysermancer hp %d resource %d move %.2f power %.2f" % [
		p_hp, Balance.max_resource(priest), Balance.move_speed(priest), Balance.attack_power(priest, CG.DamageType.DIVINE),
		g_hp, Balance.max_resource(geyser), Balance.move_speed(geyser), Balance.attack_power(geyser, CG.DamageType.WATER)])
	assert_true(Balance.max_resource(priest) > Balance.max_resource(geyser),
		"the Priest's pool is not the larger one")
	assert_true(Balance.attack_power(geyser, CG.DamageType.WATER) > Balance.attack_power(priest, CG.DamageType.DIVINE),
		"the Geysermancer does not hit harder")
	assert_true(Balance.move_speed(geyser) > Balance.move_speed(priest),
		"the Geysermancer is not the faster one")
	assert_true(g_hp < p_hp, "the Priest does not have more health")


func test_an_unedited_priest_and_geysermancer_do_not_cast_the_same_things() -> void:
	var priest := _casts(&"priest", false)
	var geyser := _casts(&"geysermancer", false)
	print("unedited casts: priest %s  geysermancer %s" % [priest, geyser])
	assert_ne(priest.keys(), geyser.keys(), "the two casters fired the same action set with no rows")


## The half of #406 that is real: the Priest gets its role from the fallback's
## heal branch, and the Geysermancer has one action and no second thing to do.
func test_an_unedited_geysermancer_fires_only_its_weapon() -> void:
	var geyser := _casts(&"geysermancer", false)
	assert_eq(geyser.keys().size(), 1, "unedited Geysermancer cast set: %s" % [geyser])
	assert_true(geyser.has(&"geyser_spout"), "the one action is not the Orb's attack: %s" % [geyser])


## Issue 406: the library is read top down and it is priority order once added,
## so the first row is what the class says it is. The Geysermancer led with a
## conditional cleanse; it now leads with the fire pair that defines it.
func test_a_dps_library_leads_with_a_damaging_row() -> void:
	for class_id in [&"geysermancer", &"priest"]:
		var library := PresetPlans.for_class(class_id)
		assert_false(library.is_empty(), "%s has no library" % class_id)
		var first: ActionDef = Registry.get_action(_action_of(library[0]))
		assert_not_null(first, "%s's first library row names no action" % class_id)
		var wants_damage := Registry.get_class_def(class_id).role_primary == CG.Role.DPS
		assert_eq(first.power_scale > 0.0 and not first.heals, wants_damage,
			"%s leads with %s" % [class_id, first.id])


func _action_of(plan: Plan) -> StringName:
	for b in plan.blocks:
		if b is UseActionBlock:
			var a: ActionDef = (b as UseActionBlock).action
			return a.id if a != null else &""
	return &""
