extends "res://Tests/TestCase.gd"

## Issue 840. Restart rolls a fresh seed and opens the party screen, which is
## where party, room and seed are chosen; "Change party" is that flow's second
## half rather than a control of its own.

const MainScene := preload("res://Scenes/Main.tscn")

func _main_in_a_fight() -> Node:
	var main = in_tree(MainScene.instantiate())
	var screen = main._current
	screen.prefill_seed("0000002A")
	screen.toggle_pawn(screen.available_pawns()[0], true)
	main.start_battle(screen.current_config())
	return main

func test_restart_rolls_a_seed_that_is_not_the_one_just_watched() -> void:
	var main := _main_in_a_fight()
	main.rerun()
	assert_ne(main.run_config.seed_text(), "0000002A",
		"Restart re-entered the same fight: the seed never moved")

func test_restart_opens_the_party_screen_with_that_seed_in_the_field() -> void:
	var main := _main_in_a_fight()
	main.rerun()
	var screen = main._current
	assert_true(screen.get_script().resource_path.ends_with("PartySelect.gd"),
		"Restart went straight back into a fight instead of the restart flow")
	assert_eq(screen.current_config().seed_text(), main.run_config.seed_text(),
		"the field shows a different seed than the one Restart rolled")

## The half of the flow that used to be "Change party": the pawns, their plans
## and the room come back so Start is one click away.
func test_the_restart_flow_keeps_the_party_and_the_room() -> void:
	var main := _main_in_a_fight()
	var picked: PawnData = main.run_config.party[0]
	var room: StringName = main.run_config.encounter_id
	main.rerun()
	var screen = main._current
	assert_eq(screen.selected_pawns().size(), 1, "the party came back empty")
	assert_true(screen.selected_pawns()[0] == picked, "a different pawn object came back")
	assert_eq(screen.selected_room(), room, "the room reset")

## The seed round-trips as text, so a roll the field cannot represent would show
## the player one fight and start another.
func test_the_rolled_seed_survives_the_trip_through_the_field() -> void:
	var main := _main_in_a_fight()
	for i in 8:
		main.rerun()
		var shown = main._current.current_config().seed
		assert_eq(shown, main.run_config.seed, "the field truncated the rolled seed")
		main.start_battle(main._current.current_config())

## The end card names the fight that just ended, in the spelling the seed field
## parses, so a player who wants it again can read it and type it back.
func test_the_end_card_names_the_seed_of_the_fight_that_just_ended() -> void:
	var main := _main_in_a_fight()
	var view = main._current
	view._show_outcome()
	assert_eq(view._end_seed_label.text, "Seed 0000002A")
	assert_eq(RunConfig.parse_seed("0000002A"), main.run_config.seed,
		"the card shows a seed the field cannot turn back into this fight")

## `Main.rerun` rolls the new seed into the very RunConfig the finished fight
## was run from, so a card that re-reads that object names a fight nobody has
## watched. Mutated here between the first tick and the outcome, because that is
## the window a lazy read would lose.
func test_the_end_card_names_the_fight_that_ran_not_whatever_the_config_says_now() -> void:
	var main := _main_in_a_fight()
	var view = main._current
	main.run_config.seed = 0x0BADBEEF
	view._show_outcome()
	assert_eq(view._end_seed_label.text, "Seed 0000002A",
		"the card read the seed back off a config that had already been re-rolled")

## And end to end: the seed on the card is still the watched one after Restart.
func test_restart_does_not_relabel_the_card_it_was_pressed_on() -> void:
	var main := _main_in_a_fight()
	var view = main._current
	view._show_outcome()
	var watched: String = view._end_seed_label.text
	main.rerun()
	assert_eq(view._end_seed_label.text, watched,
		"the end card relabelled itself with the seed of a fight nobody has watched")
	assert_ne(main.run_config.seed_text(), "0000002A", "rerun did not roll at all")

func test_neither_the_end_card_nor_the_escape_menu_offers_change_party() -> void:
	var main := _main_in_a_fight()
	var view = main._current
	var labels: Array[String] = view._pause_menu.button_labels()
	for label in labels:
		assert_false(label.to_lower().begins_with("change"),
			"the pause menu still has '%s'" % label)
	for node in _all_buttons(view):
		assert_false(node.text.to_lower().begins_with("change"),
			"the battle screen still has a '%s' button" % node.text)

func _all_buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	if root is Button:
		out.append(root)
	for child in root.get_children():
		out.append_array(_all_buttons(child))
	return out
