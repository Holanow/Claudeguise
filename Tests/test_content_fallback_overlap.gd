extends "res://Tests/TestCase.gd"


## Issue 433: whether a class's top library row changes the fight at all. A row
## that restates a hidden default reads to the player as an edit that did
## nothing, which breaks the author-watch-adjust loop on the first turn.


const SEEDS := 8

## Two classes overlap nothing: their top row names an action the fallback
## cannot reach at all, so it is an edit the player can see land.
func test_two_classes_lead_with_a_row_the_fallback_cannot_cast_at_all() -> void:
	for class_id in [&"geysermancer", &"siege_master"]:
		var library := PresetPlans.for_class(class_id)
		var fired := _unedited_casts(class_id)
		assert_false(fired.has(_action_of(library[0])),
			"%s's top row is cast by the fallback too" % class_id)


## Issue 433: what keeps the Priest's row and the Warrior's Second Wind out of
## the fallback's shadow is a threshold above it, and nothing else. At or below
## `HEAL_THRESHOLD_FRACTION` the fallback casts the same heal at the same ally
## on the same tick, so either number crossing it makes the row inert again.
func test_both_heal_rows_fire_above_the_fallbacks_own_threshold() -> void:
	for fraction in [PresetPlans.HEAL_ABOVE_FALLBACK, PresetPlans.SECOND_WIND_ABOVE_FALLBACK]:
		assert_true(fraction > DefaultBehavior.HEAL_THRESHOLD_FRACTION,
			"%f is at or under the fallback's %f, so the row restates it" % [
				fraction, DefaultBehavior.HEAL_THRESHOLD_FRACTION])


## The Warrior's Taunt row asks for the Taunt's own reach, so it cannot order a
## shout that reaches nobody. Read off the registry rather than retyped.
func test_the_taunt_row_asks_for_the_taunts_own_radius() -> void:
	var top := PresetPlans.for_class(&"warrior")[0]
	assert_eq(top.condition.op, &"enemy_in_range", "the Warrior no longer leads with a ranged condition")
	assert_eq(float(top.condition.args["range"]), Registry.get_action(&"warrior_taunt").taunt_radius,
		"the Taunt row's range has drifted from warrior_taunt's taunt_radius")


## Every action a party of unedited pawns of one class fired, read off the
## finished event stream rather than off live unit state.
func _unedited_casts(class_id: StringName) -> Dictionary:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	var out := {}
	for s in SEEDS:
		var party: Array[PawnData] = []
		for i in 4:
			party.append(PawnFactory.make_starter_pawn(
				class_id, StringName("%s_%d" % [class_id, i]), String(class_id)))
		var state := CombatSim.build(party, encounter, s)
		CombatSim.run(state)
		for e in state.events:
			if e.kind != CG.EventKind.ACTION_FIRE:
				continue
			var u := state.unit(e.source_id)
			if u != null and u.pawn != null:
				out[e.action_id] = int(out.get(e.action_id, 0)) + 1
	return out


func _action_of(plan: Plan) -> StringName:
	for b in plan.blocks:
		if b.kind == PlanBlock.Kind.ACTION:
			return b.args.get("action_id", &"")
	return &""
