extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 441. After #399 the plan editor starts empty, so a new player's first
## fight is one hundred percent unplanned, and the only word the game used for
## that was `[fallback]`.

func _starter_party(size: int = 4) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for cid in Registry.all_class_ids().slice(0, size):
		party.append(PawnFactory.make_starter_pawn(
			cid, StringName("%s" % cid), Registry.get_class_def(cid).display_name))
	return party

func _unstamped_action(source_id: int) -> CombatEvent:
	var e := CombatEvent.make(CG.EventKind.ACTION_START, 4)
	e.source_id = source_id
	e.action_id = &"warrior_strike"
	return e

func _one_pawn_state(pawn: PawnData) -> CombatState:
	var state := CombatState.new(1)
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.display_name = pawn.display_name
	u.pawn = pawn
	state.units.append(u)
	return state

# ---------------------------------------------------------------------------
# 1. The tag says what it means
# ---------------------------------------------------------------------------

## A pawn whose editor is empty is the state the whole issue is about, and the
## tag is the only place the game ever mentions it.
func test_a_pawn_with_no_plans_says_it_has_none() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"w", "Warrior")
	assert_true(pawn.plans.is_empty(), "a starter pawn is the empty-editor case")
	var state := _one_pawn_state(pawn)
	var view := CombatLogView.new()
	var line := view.line_for_event(state, _unstamped_action(0))
	assert_true(line.contains("[no plan]"), line)
	assert_false(line.to_lower().contains("fallback"), line)

## And a pawn that HAS written rows, none of which matched, is a different
## answer to "why did that happen": its own default, not an empty editor.
func test_a_pawn_whose_rows_all_missed_reads_as_its_default() -> void:
	var pawn := PawnFactory.make_preset_pawn(&"warrior", &"w", "Warrior")
	assert_false(pawn.plans.is_empty(), "a preset pawn is the authored case")
	var state := _one_pawn_state(pawn)
	var view := CombatLogView.new()
	var line := view.line_for_event(state, _unstamped_action(0))
	assert_true(line.contains("[default]"), line)
	assert_false(line.contains("[no plan]"), line)
	assert_false(line.to_lower().contains("fallback"), line)

## The word is gone from the log altogether, checked against a whole real
## fight rather than a hand-built event.
func test_no_line_in_a_real_fight_says_fallback() -> void:
	var state := CombatSim.build(
		_starter_party(), Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 155)
	CombatSim.run(state)
	var view := CombatLogView.new()
	var unplanned := 0
	for e in state.events:
		var line := view.line_for_event(state, e)
		assert_false(line.to_lower().contains("fallback"), line)
		if line.contains("[no plan]"):
			unplanned += 1
	assert_true(unplanned > 0, "no unplanned pawn action, so the wording went unexercised")

## The plan editor used the same jargon for the same row.
func test_the_plan_editor_does_not_call_it_a_fallback_either() -> void:
	assert_false(InspectPanel.HOW_TO_PLAY.to_lower().contains("fallback"),
		InspectPanel.HOW_TO_PLAY)
	assert_false(InspectPanel.DEFAULT_ROW_TITLE.to_lower().contains("fallback"),
		InspectPanel.DEFAULT_ROW_TITLE)

# ---------------------------------------------------------------------------
# 2. Something points at the plan editor
# ---------------------------------------------------------------------------

func test_the_end_card_points_at_the_plan_editor_when_nobody_has_a_plan() -> void:
	var state := CombatSim.build(
		_starter_party(), Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 155)
	var prompt := BattleView.plans_prompt(state)
	assert_true(prompt.contains("Plans"), "the prompt must name the button that opens the editor: %s" % prompt)
	assert_true(prompt.to_lower().contains("plan"), prompt)

## The negative half. A prompt that fires on a player who has already written
## plans is furniture, and furniture is how the real case goes invisible.
func test_the_end_card_says_nothing_when_every_pawn_has_a_plan() -> void:
	var party: Array[PawnData] = []
	for cid in Registry.all_class_ids().slice(0, 4):
		party.append(PawnFactory.make_preset_pawn(
			cid, StringName("%s" % cid), Registry.get_class_def(cid).display_name))
	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 155)
	assert_eq(BattleView.plans_prompt(state), "")

## A partial editor is heron's measured worst case, so it must not read as the
## all-empty one.
func test_a_partly_planned_party_is_counted_not_rounded() -> void:
	var party := _starter_party()
	party[0].plans = PresetPlans.for_class(party[0].pawn_class.id).slice(0, 1)
	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 155)
	var prompt := BattleView.plans_prompt(state)
	assert_true(prompt.contains("3"), "3 of the 4 pawns have no plan: %s" % prompt)

## A Siege Engine has no pawn and cannot be planned, so it must not be counted
## as a pawn without a plan.
func test_a_summon_is_not_a_pawn_missing_a_plan() -> void:
	var party: Array[PawnData] = []
	for cid in Registry.all_class_ids().slice(0, 2):
		party.append(PawnFactory.make_preset_pawn(
			cid, StringName("%s" % cid), Registry.get_class_def(cid).display_name))
	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 155)
	var summon := CombatUnit.new()
	summon.id = 900
	summon.team = CG.Team.PLAYER
	summon.display_name = "Siege Engine"
	state.units.append(summon)
	assert_eq(BattleView.plans_prompt(state), "",
		"the summon has no plans by construction and must not raise the prompt")

## Through the screen, not the function under it: the card has to actually
## carry the words after the fight resolves.
func test_the_end_card_shows_the_prompt_when_the_fight_resolves() -> void:
	var view = in_tree(BattleScene.instantiate())
	var state := CombatSim.build(
		_starter_party(), Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 155)
	CombatSim.run(state)
	view.state = state
	view._show_outcome()
	assert_true(view._end_prompt_label.visible, "the prompt label must not be hidden")
	assert_true(view._end_prompt_label.text.contains("Plans"), view._end_prompt_label.text)

func test_the_end_card_hides_the_prompt_for_a_planned_party() -> void:
	var view = in_tree(BattleScene.instantiate())
	var party: Array[PawnData] = []
	for cid in Registry.all_class_ids().slice(0, 4):
		party.append(PawnFactory.make_preset_pawn(
			cid, StringName("%s" % cid), Registry.get_class_def(cid).display_name))
	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 155)
	CombatSim.run(state)
	view.state = state
	view._show_outcome()
	assert_false(view._end_prompt_label.visible,
		"a player who has written plans must not be told to write plans: %s" % view._end_prompt_label.text)

## The prompt lives on the end card, which is a modal. The field is the one
## place it must not appear: the same tester's first complaint was that the
## defaults cover the arena with text.
func test_the_prompt_is_not_on_the_field_during_the_fight() -> void:
	var view = in_tree(BattleScene.instantiate())
	assert_false(view._end_prompt_label.visible,
		"nothing about plans may print before the fight resolves")
