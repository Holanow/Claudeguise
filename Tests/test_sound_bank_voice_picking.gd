extends "res://Tests/TestCase.gd"

## Issue 569: the round robin took `_next_voice` unconditionally, stealing a
## busy voice while an idle one sat a slot away. `pick_voice_index` is the
## fix; pure and static so it is testable without an `AudioStreamPlayer`,
## which does not report `.playing` correctly under the dummy headless driver.

func test_prefers_an_idle_voice_over_the_round_robin_pointer() -> void:
	var playing := [true, true, false, true]
	var idx := SoundBank.pick_voice_index(playing, 0)
	assert_eq(idx, 2, "an idle voice at index 2 was not chosen over busy index 0")

func test_finds_the_idle_voice_wrapping_past_the_end() -> void:
	var playing := [true, true, true, false]
	var idx := SoundBank.pick_voice_index(playing, 2)
	assert_eq(idx, 3, "the only idle voice, past the pointer, was not found")

func test_steals_the_pointer_voice_when_every_voice_is_busy() -> void:
	var playing := [true, true, true, true]
	var idx := SoundBank.pick_voice_index(playing, 1)
	assert_eq(idx, 1, "with nothing idle, the pointer's own voice should be taken")

func test_the_first_call_with_nothing_playing_takes_the_pointer() -> void:
	var playing := [false, false, false, false]
	var idx := SoundBank.pick_voice_index(playing, 3)
	assert_eq(idx, 3, "an idle bank should still hand back the pointer's voice")

func test_play_for_counts_a_steal_only_when_it_actually_steals() -> void:
	var holder := Node.new()
	var bank = SoundBank.attach(in_tree(holder))
	var hit := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	hit.action_id = &"warrior_strike"
	# Eight distinct ticks so `_played_this_tick` dedup never suppresses a play.
	for t in SoundBank.VOICES:
		var e := CombatEvent.make(CG.EventKind.DAMAGE, t)
		e.action_id = &"warrior_strike"
		bank.play_for(e)
	assert_eq(bank.steals(), 0,
		"filling exactly VOICES empty voices stole %d times, expected 0" % bank.steals())
