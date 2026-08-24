extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 550. `SoundBank` had no caller in the shipping game for months while its
## README told the player the game made seven noises. These are the assertions
## that would have gone red the whole time.

func _view_with_state() -> Node:
	var state := CombatState.new(1)
	var view = in_tree(BattleScene.instantiate())
	view.state = state
	view.event_cursor = 0
	return view

func _voices(view: Node) -> Array:
	var out: Array = []
	var holder := view.get_node_or_null("Sound")
	if holder == null:
		return out
	for child in holder.get_children():
		if child is AudioStreamPlayer:
			out.append(child)
	return out


func test_the_battle_screen_owns_a_bank_of_voices() -> void:
	var view := _view_with_state()
	assert_eq(_voices(view).size(), SoundBank.VOICES,
		"the battle screen has no players to make a sound with")


func test_an_audible_event_reaches_a_voice() -> void:
	# Through `consume_events`, which is the path the running game takes, rather
	# than by calling the bank: the defect this closes was that nothing called
	# the bank at all, and a test that calls it directly cannot see that.
	var view := _view_with_state()
	for voice in _voices(view):
		assert_eq(voice.stream, null, "a voice already holds a stream before the fight starts")

	var hit := CombatEvent.make(CG.EventKind.DAMAGE, 5)
	hit.action_id = &"warrior_strike"
	view.state.emit(hit)
	view.consume_events()

	var loaded := 0
	for voice in _voices(view):
		if voice.stream != null:
			loaded += 1
	assert_eq(loaded, 1, "a DAMAGE event put %d streams on the voices, expected 1" % loaded)


func test_a_deliberately_silent_event_reaches_no_voice() -> void:
	# The negative half, and the one that matters most here: `play_for` is handed
	# every event unfiltered, so a bank that played everything would look
	# identical to a bank that plays the right things.
	var view := _view_with_state()
	var drain := CombatEvent.make(CG.EventKind.DAMAGE, 5)
	view.state.emit(drain)
	var start := CombatEvent.make(CG.EventKind.ACTION_START, 5)
	start.action_id = &"warrior_strike"
	view.state.emit(start)
	view.consume_events()

	for voice in _voices(view):
		assert_eq(voice.stream, null,
			"a damage-over-time tick or an ACTION_START made a noise")
