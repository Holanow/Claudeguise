extends "res://Tests/TestCase.gd"


## Issue 433: which library rows cast an action the fallback was already
## casting. A row that restates a hidden default reads to the player as an edit
## that did nothing, which breaks the author-watch-adjust loop on the first
## turn.
##
## Action overlap is the cause, not the symptom: a row can share the fallback's
## action and still change the fight by aiming it elsewhere, which is what the
## Abomination's Claw row does. Whether a row changes anything is an outcome
## digest, and `Tools/PlanGap.gd` is the instrument for that.


const SEEDS := 8

## The library actions `DefaultBehavior` already fires for an unedited pawn of
## that class, as measured below. Three classes of five, and in each the row is
## the one its library leads with.
##
## This is a record of today, not a rule. It fires the day the fallback stops
## reaching one of these or starts reaching another.
const FALLBACK_ALREADY_CASTS := {
	&"warrior": [&"warrior_second_wind"],
	&"priest": [&"priest_heal"],
	&"abomination": [&"abomination_claw", &"abomination_hook"],
	&"geysermancer": [],
	&"siege_master": [],
}


func test_the_fallback_already_casts_four_of_the_twenty_library_actions() -> void:
	var total_rows := 0
	for class_id in Registry.all_class_ids():
		total_rows += PresetPlans.for_class(class_id).size()
		var overlap := _fallback_overlap(class_id)
		print("%-14s fallback already casts %s" % [String(class_id), overlap])
		assert_eq(overlap, _expected(class_id),
			"%s: the fallback's overlap with the library moved" % class_id)
	assert_eq(total_rows, 20, "the library changed size; re-read the partition above")


## The harm the issue names. Every class that overlaps at all overlaps on the
## row it leads with, so the first row a new player adds is one the pawn was
## already doing. The Abomination also overlaps on Hook, four rows down.
func test_every_class_that_overlaps_overlaps_on_the_row_it_leads_with() -> void:
	for class_id in Registry.all_class_ids():
		var overlap := _fallback_overlap(class_id)
		if overlap.is_empty():
			continue
		var library := PresetPlans.for_class(class_id)
		assert_false(library.is_empty(), "%s has no library" % class_id)
		assert_true(overlap.has(_action_of(library[0])),
			"%s's overlap has moved off its top row: %s" % [class_id, overlap])


## The negative half. Two classes overlap nothing, so a green run above is not
## the detector reporting everything as a duplicate.
func test_two_classes_lead_with_a_row_the_fallback_cannot_cast_at_all() -> void:
	for class_id in [&"geysermancer", &"siege_master"]:
		var library := PresetPlans.for_class(class_id)
		var fired := _unedited_casts(class_id)
		assert_false(fired.has(_action_of(library[0])),
			"%s's top row is cast by the fallback too" % class_id)


## Why the Warrior's and the Priest's rows are the inert pair and the
## Abomination's is not: those two also aim where the fallback aims, so nothing
## about the cast differs. Claw picks an unpoisoned enemy instead of the
## nearest one.
func test_the_inert_pair_also_share_the_fallbacks_targeting() -> void:
	for class_id in [&"warrior", &"priest"]:
		var top := PresetPlans.for_class(class_id)[0]
		assert_true(_targeting_of(top) in [&"target_self", &"target_lowest_hp_fraction_ally"],
			"%s's top row no longer aims where the fallback's heal aims" % class_id)
	var claw := PresetPlans.for_class(&"abomination")[0]
	assert_eq(_targeting_of(claw), &"target_enemy_without_status",
		"Claw no longer re-aims, so it may now be inert as well")


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


## The class's library actions that an unedited pawn of that class already
## casts, sorted so the comparison does not depend on firing order.
func _fallback_overlap(class_id: StringName) -> Array:
	var fired := _unedited_casts(class_id)
	var out := []
	for plan in PresetPlans.for_class(class_id):
		var action_id := _action_of(plan)
		if fired.has(action_id) and not out.has(action_id):
			out.append(action_id)
	out.sort()
	return out


func _expected(class_id: StringName) -> Array:
	var out := []
	for id in FALLBACK_ALREADY_CASTS[class_id]:
		out.append(id)
	out.sort()
	return out


func _action_of(plan: Plan) -> StringName:
	for b in plan.blocks:
		if b.kind == PlanBlock.Kind.ACTION:
			return b.args.get("action_id", &"")
	return &""


func _targeting_of(plan: Plan) -> StringName:
	for b in plan.blocks:
		if b.kind == PlanBlock.Kind.TARGETING:
			return b.op
	return &""
