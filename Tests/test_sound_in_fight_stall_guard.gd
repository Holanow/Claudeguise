extends "res://Tests/TestCase.gd"

## Issue 571: SoundInFight once reached tick 17 of ~450 and reported its counts
## as an ordinary quiet fight. `SoundInFight.is_stalled` is the guard; this
## proves it fires on the reported shape and stays quiet on healthy shapes,
## in both directions, per ENGINEER.md.

const SoundInFightScript := preload("res://Tools/SoundInFight.gd")
const UNRESOLVED := CombatState.Outcome.UNRESOLVED
const WON := CombatState.Outcome.PLAYER_WIN

func test_fires_on_the_reported_shape() -> void:
	# The exact numbers #571 disclosed: 1800 frames spent, tick 17 reached,
	# against a fight that normally finishes around tick 450.
	assert_true(SoundInFightScript.is_stalled(UNRESOLVED, 1800, 1800, 17, 4),
		"a fight stuck at tick 17 of a 1800-frame budget was not flagged")

func test_stays_quiet_on_a_healthy_unresolved_run() -> void:
	# wren's baseline runs: 305 and 359 ticks reached inside the same budget.
	assert_false(SoundInFightScript.is_stalled(UNRESOLVED, 1800, 1800, 305, 4),
		"a fight that reached tick 305 of ~450 was wrongly flagged as stalled")
	assert_false(SoundInFightScript.is_stalled(UNRESOLVED, 1800, 1800, 359, 4),
		"a fight that reached tick 359 of ~450 was wrongly flagged as stalled")

func test_stays_quiet_when_the_fight_simply_resolved() -> void:
	# Ending early because the fight is OVER is not a stall.
	assert_false(SoundInFightScript.is_stalled(WON, 400, 1800, 90, 4),
		"a fight that ended on its own was flagged as stalled")

func test_stays_quiet_when_frames_were_not_all_spent() -> void:
	# Breaking out of the frame loop early (outcome resolved) never reaches
	# frame_budget, so this shape should not occur, but the guard must not
	# fire on it if it somehow did -- frames_spent alone is not "stuck".
	assert_false(SoundInFightScript.is_stalled(UNRESOLVED, 900, 1800, 17, 4),
		"a run that has not yet spent its whole budget was flagged as stalled")
