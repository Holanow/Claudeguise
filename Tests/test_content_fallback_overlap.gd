extends "res://Tests/TestCase.gd"


## Issue 433: whether a class's top library row changes the fight at all. A row
## that restates a hidden default reads to the player as an edit that did
## nothing, which breaks the author-watch-adjust loop on the first turn.
##
## The outcome digest is the check that answers it; the action overlap below is
## a record of where the fallback and the library reach for the same spell, and
## a row can share an action and still be a real edit.


const SEEDS := 8

## The library actions `DefaultBehavior` already fires for an unedited pawn of
## that class, as measured below. Sharing an action is no longer the same thing
## as being inert -- since #433 the Priest's row shares `priest_heal` and fires
## at a threshold the fallback does not reach.
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


## **The check that actually answers the issue, and the two below it cannot.**
## A row shares the fallback's action and still changes the fight when it aims
## somewhere else (the Abomination's Claw) or fires at a different moment (the
## Priest's heal since #433). Only the outcome tells those apart.

## **INVERTED PARK, ISSUE 565.** The Geysermancer's top row produces a
## bit-identical fight. **The Priest left this set on #562 and NOT because
## anybody made its row matter**: every party here carries an Abomination, whose
## hook now drags over seven ticks, so all sixteen fights moved under a
## measurement that was already deciding on 4 health points. #565's premise
## needs re-measuring rather than closing.
func test_the_geysermancer_top_row_changes_nothing_issue_565() -> void:
	var unedited := _digest(&"", false)
	var inert := []
	for class_id in Registry.all_class_ids():
		var top_row := _digest(class_id, true)
		print("%-14s unedited %d  top row alone %d" % [String(class_id), unedited, top_row])
		if top_row == unedited:
			inert.append(class_id)
	assert_eq(inert, [&"geysermancer"],
		"the set of inert top rows has moved; re-measure #565 before reading that as a fix")


## The negative half. Two classes overlap nothing, so a green run above is not
## the detector reporting everything as a duplicate.
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


## `Tools/PlanGap.gd`'s fold, over one room instead of six: an order-sensitive
## digest of every fight's outcome, length and end-of-fight party health. Two
## arms with the same digest ran the same fights.
func _digest(class_id: StringName, top_row: bool) -> int:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	var digest := 0
	for s in SEEDS:
		var party: Array[PawnData] = []
		for cid in Registry.all_class_ids():
			var pid := StringName("%s_%d" % [cid, party.size()])
			if not top_row or cid != class_id:
				party.append(PawnFactory.make_starter_pawn(cid, pid, String(cid)))
				continue
			var pawn := PawnFactory.make_preset_pawn(cid, pid, String(cid))
			var one: Array[Plan] = [pawn.plans[0]]
			pawn.plans = one
			party.append(pawn)
		var state := CombatSim.build(party, encounter, s)
		var outcome := CombatSim.run(state)
		digest = (digest * 131 + outcome * 1000003 + state.tick * 101 + _hp_percent(state)) % 1000000007
	return digest


static func _hp_percent(state: CombatState) -> int:
	var h := 0
	var h_max := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER or u.pawn == null:
			continue
		h += maxi(0, u.hp)
		h_max += u.hp_max
	return 0 if h_max <= 0 else int(round(100.0 * float(h) / float(h_max)))
