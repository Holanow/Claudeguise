extends "res://Tests/TestCase.gd"


## **Every duration an ability's description told the player was exactly half the
## truth, on ten of the fourteen actions that state one.**
##
## Issue 77 halved `CG.TICKS_PER_SECOND` from 30 to 15 at the player's request --
## *"halve fight speed"* -- and every tick count in `Scripts/Content` was left
## alone on purpose, because that is what preserves the relative timing of
## everything against everything else. What nobody checked was the **prose**: a
## description reading "for 3 seconds" beside `status_duration_ticks = 90` was
## true at 30 ticks a second and has said 3 where the game means 6 ever since.

## Phrase -> which of the action's own tick counts it is talking about.
const _PATTERNS := [
	{"re": "(?<!again )for ([0-9]+(?:\\.[0-9]+)?) seconds?", "field": "status"},
	{"re": "again for (?:another )?([0-9]+(?:\\.[0-9]+)?) seconds?", "field": "cooldown"},
	{"re": "Spends ([0-9]+(?:\\.[0-9]+)?) seconds? (?:building|drawing)", "field": "wind_up"},
	{"re": "once every ([0-9]+(?:\\.[0-9]+)?) seconds?", "field": "cycle"},
]

## Actions whose description states a poison rate per second. Derived from
## the POISON `StatusDef`'s own number in the assertion, not retyped.
const _POISON_RATE_ACTIONS := [&"abomination_claw", &"cultist_bolt"]

func test_every_duration_in_an_ability_description_matches_its_own_ticks() -> void:
	var checked := 0
	for id in ActionLibrary.all_ids():
		var action := ActionLibrary.get_action(id)
		var text: String = action.description
		var claimed := 0
		for pattern in _PATTERNS:
			var re := RegEx.new()
			re.compile(pattern["re"])
			for m in re.search_all(text):
				claimed += 1
				checked += 1
				var text_number := m.get_string(1)
				var stated := float(text_number)
				var ticks := _ticks_for(action, pattern["field"])
				assert_true(ticks > 0, "%s says '%s' but carries no %s ticks" % [id, m.get_string(0), pattern["field"]])
				## Compared at the precision the sentence itself uses: "0.5
				## seconds" against 8 ticks is 0.533 rounded to one decimal and
				## is correct, while "3 seconds" against 90 ticks is 6.0 and is
				## not. Snapping rather than a fixed epsilon keeps this exact --
				## a tolerance wide enough for 0.533 would also swallow a real
				## error on a short duration.
				var real := float(ticks) * CG.TICK_SECONDS
				var step := _step_for(text_number)
				assert_almost_eq(
					stated, snappedf(real, step), step * 0.01,
					"%s says %s seconds where its %d ticks are %.2f" % [id, text_number, ticks, real]
				)
		# The half that stops this rotting: a duration written a way none of the
		# patterns above knows is not silently exempt.
		var loose := RegEx.new()
		loose.compile("([0-9]+(?:\\.[0-9]+)?) seconds?")
		assert_eq(
			loose.search_all(text).size(), claimed,
			"%s states a duration in a phrasing this test does not recognise: %s" % [id, text]
		)
	# Non-vacuity. Ten of these were wrong when the test was written; a build
	# where the walk finds nothing must not read as a pass.
	assert_true(checked >= 10, "only %d durations were checked, the walk found nothing" % checked)

func test_the_poison_rate_a_description_promises_is_the_rate_it_deals() -> void:
	var Balance = load("res://Scripts/Content/Balance.gd")
	var per_second: float = StatusLibrary.of(CG.Status.POISON).damage_percent_of_max_hp_per_tick * float(CG.TICKS_PER_SECOND)
	var re := RegEx.new()
	re.compile("([0-9]+(?:\\.[0-9]+)?)% of its max health per second")
	for id in _POISON_RATE_ACTIONS:
		var action := ActionLibrary.get_action(id)
		assert_not_null(action, "%s should exist" % id)
		var m := re.search(action.description)
		assert_not_null(m, "%s should state a poison rate per second: %s" % [id, action.description])
		assert_almost_eq(
			float(m.get_string(1)), per_second, 0.01,
			"%s promises %s%% a second where the constant deals %.2f%%" % [id, m.get_string(1), per_second]
		)

## The place value of the last digit the sentence prints: "16" -> 1.0,
## "0.5" -> 0.1. What the description is claiming is the real duration rounded
## to this, and nothing finer.
func _step_for(text_number: String) -> float:
	var dot := text_number.find(".")
	if dot < 0:
		return 1.0
	return pow(10.0, -(text_number.length() - dot - 1))

func _ticks_for(action, field: String) -> int:
	match field:
		"status":
			return action.status_duration_ticks
		"wind_up":
			return action.wind_up_ticks
		"cooldown":
			return action.cooldown_ticks
		"cycle":
			return action.wind_up_ticks + action.recover_ticks
	return 0
