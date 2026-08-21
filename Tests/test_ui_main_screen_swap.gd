extends "res://Tests/TestCase.gd"

## Issue 380. "Change party" swapped in a brand new PartySelect, whose _ready()
## rebuilt every pawn through PawnFactory, so the plans the player had just
## written were thrown away. The playtester wrote the Warrior's four rows three
## times. Only the seed survived, because Main round-trips it on purpose --
## which is the pattern the rest of this state now follows.

const MainScene := preload("res://Scenes/Main.tscn")

func _main() -> Node:
	var main = MainScene.instantiate()
	main._ready()
	return main

func _authored_plan() -> Plan:
	var plan := Plan.new()
	plan.id = &"wren_380_marker"
	plan.display_name = "A row the player wrote"
	return plan

## The whole issue in one test: write a row, leave, come back, read it.
func test_change_party_keeps_the_plan_the_player_wrote() -> void:
	var main := _main()
	var screen = main._current
	var pawn: PawnData = screen.available_pawns()[0]
	pawn.plans = [_authored_plan()]
	screen.toggle_pawn(pawn, true)
	main.start_battle(screen.current_config())
	main.show_party_select()
	var again = main._current
	var back: PawnData = again.available_pawns()[0]
	assert_true(back == pawn, "the roster was rebuilt: this is a different object")
	assert_eq(back.plans.size(), 1, "the authored row was thrown away")
	assert_eq(back.plans[0].id, &"wren_380_marker")
	main.free()

func test_change_party_keeps_the_party_that_was_picked() -> void:
	var main := _main()
	var screen = main._current
	var pawn: PawnData = screen.available_pawns()[0]
	screen.toggle_pawn(pawn, true)
	main.start_battle(screen.current_config())
	main.show_party_select()
	var again = main._current
	assert_eq(again.selected_pawns().size(), 1, "the party came back empty")
	assert_true(again.selected_pawns()[0] == pawn)
	assert_true(again._cards[pawn.id].selected, "the card must show it is picked")
	main.free()

func test_change_party_keeps_the_room_that_was_chosen() -> void:
	var main := _main()
	var screen = main._current
	var rooms := PartySelect.offered_rooms()
	var other: StringName = &""
	for id in rooms:
		if id != CG.DEFAULT_ENCOUNTER:
			other = id
			break
	if other == &"":
		main.free()
		return
	screen.select_room(other)
	screen.toggle_pawn(screen.available_pawns()[0], true)
	main.start_battle(screen.current_config())
	main.show_party_select()
	assert_eq(main._current.selected_room(), other,
		"switching rooms means going through Change party, and it reset to room 1")
	main.free()

## The control. This one already worked, and it is the pattern the three above
## now copy: if it ever fails, the harness is wrong rather than the fix.
func test_change_party_keeps_the_seed() -> void:
	var main := _main()
	var screen = main._current
	screen.prefill_seed("0000002A")
	screen.toggle_pawn(screen.available_pawns()[0], true)
	main.start_battle(screen.current_config())
	main.show_party_select()
	assert_eq(main._current.current_config().seed_text(), "0000002A")
	main.free()

## The first visit has nothing to restore and must still build a roster.
func test_the_first_visit_builds_a_roster_of_its_own() -> void:
	var main := _main()
	assert_true(main._current.available_pawns().size() > 0,
		"party select with no roster to restore showed no classes")
	main.free()
