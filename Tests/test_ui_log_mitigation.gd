extends "res://Tests/TestCase.gd"

## Issue 344's rendering half. The log showed "(28 before mitigation)" and
## refused to say what took the 28. swift's simulation half (#362, #363) found
## that in 13.4% of 22,562 hits part or all of that gap was **overkill, which
## nothing caused** -- including the issue's own headline case, a 29-damage
## swing landing for 1 on a Rat with 1 hp left.

const LogScript := preload("res://Scripts/UI/CombatLogView.gd")

func _view():
	var view = Control.new()
	view.set_script(LogScript)
	view._ready()
	return view

func _state() -> CombatState:
	var state := CombatState.new(0)
	state.units = [_unit(1, "Warrior"), _unit(2, "Rat")]
	return state

func _unit(id: int, display_name: String) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.display_name = display_name
	u.hp = 10
	u.hp_max = 10
	return u

func _hit(raw: int, after: int, landed: int, cause: CG.MitigationCause) -> CombatEvent:
	var e := CombatEvent.new()
	e.kind = CG.EventKind.DAMAGE
	e.source_id = 1
	e.target_id = 2
	e.damage_type = CG.DamageType.PHYSICAL
	e.amount_before_mitigation = raw
	e.amount_after_mitigation = after
	e.amount = landed
	e.mitigation_cause = cause
	return e

func _line(raw: int, after: int, landed: int, cause: CG.MitigationCause) -> String:
	var view = _view()
	var text: String = view.line_for_event(_state(), _hit(raw, after, landed, cause))
	view.free()
	return text

## ---------------------------------------------------------------------------
## Mitigation, with the cause named

func test_a_mitigated_hit_names_what_stopped_the_rest() -> void:
	var line := _line(36, 7, 7, CG.MitigationCause.HIDE)
	assert_true(line.find("36") >= 0, "the raw roll: %s" % line)
	assert_true(line.find("29") >= 0, "what was stopped: %s" % line)
	assert_true(line.findn("hide") >= 0, "the cause, named: %s" % line)

func test_each_cause_gets_its_own_word() -> void:
	var seen := {}
	for cause in [CG.MitigationCause.TOUGHNESS, CG.MitigationCause.ARMOR,
			CG.MitigationCause.HIDE, CG.MitigationCause.SHIELD, CG.MitigationCause.BLOCK]:
		var word: String = LogScript.mitigation_cause_text(cause)
		assert_ne(word, "", "%s must have a word" % CG.MitigationCause.keys()[cause])
		assert_false(seen.has(word), "two causes share the word '%s'" % word)
		seen[word] = true

## ---------------------------------------------------------------------------
## Overkill, with no cause, because nothing caused it

## The issue's headline complaint, and swift measured that it was never
## mitigation at all.
func test_overkill_is_not_reported_as_mitigation() -> void:
	var line := _line(29, 29, 1, CG.MitigationCause.NONE)
	assert_true(line.findn("mitigat") < 0, "nothing absorbed anything here: %s" % line)
	assert_true(line.find("29") >= 0, "the swing was still 29: %s" % line)
	assert_true(line.findn("had left") >= 0, "must say the target ran out: %s" % line)

func test_overkill_never_names_a_cause() -> void:
	var line := _line(109, 109, 1, CG.MitigationCause.NONE)
	for cause in [CG.MitigationCause.TOUGHNESS, CG.MitigationCause.ARMOR,
			CG.MitigationCause.HIDE, CG.MitigationCause.SHIELD, CG.MitigationCause.BLOCK]:
		assert_true(line.findn(LogScript.mitigation_cause_text(cause)) < 0,
			"overkill has no cause, and this line names one: %s" % line)

func test_a_hit_that_is_both_mitigated_and_overkill_splits_the_two() -> void:
	var line := _line(36, 20, 3, CG.MitigationCause.BLOCK)
	assert_true(line.find("16") >= 0, "36 - 20 was stopped: %s" % line)
	assert_true(line.find("17") >= 0, "20 - 3 was more than the target had: %s" % line)
	assert_true(line.findn(LogScript.mitigation_cause_text(CG.MitigationCause.BLOCK)) >= 0, line)

## ---------------------------------------------------------------------------
## The negative: a clean hit says nothing extra

func test_a_clean_hit_carries_no_parenthetical_at_all() -> void:
	var line := _line(20, 20, 20, CG.MitigationCause.NONE)
	assert_true(line.find("(") < 0, "nothing was eaten, so there is nothing to explain: %s" % line)
	assert_true(line.find("20") >= 0, line)

## An event from a path that never fills the middle figure must not invent an
## overkill of the whole hit.
func test_an_event_with_no_middle_figure_reports_only_the_mitigation_it_knows() -> void:
	var line := _line(20, 0, 12, CG.MitigationCause.TOUGHNESS)
	assert_true(line.findn("had left") < 0, "no middle figure means no overkill claim: %s" % line)
	assert_true(line.find("8") >= 0, "20 - 12 is all it can attribute: %s" % line)

## The phrase the playtester read four times, gone.
func test_the_words_before_mitigation_are_no_longer_shown() -> void:
	for line in [_line(36, 7, 7, CG.MitigationCause.HIDE), _line(29, 29, 1, CG.MitigationCause.NONE)]:
		assert_true(line.findn("before mitigation") < 0,
			"'before mitigation' says something happened and refuses to say what: %s" % line)
