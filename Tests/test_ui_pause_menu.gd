extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 825: the five toolbar buttons become one card Escape opens and Escape
## closes, and the fight is genuinely held while it is up.

func _make_party() -> Array[PawnData]:
	var cls := ClassDef.new()
	cls.id = &"test_class"
	cls.display_name = "Test Class"
	var pawn := PawnData.new()
	pawn.id = &"test_pawn"
	pawn.display_name = "Test Pawn"
	pawn.pawn_class = cls
	var out: Array[PawnData] = [pawn]
	return out

func _make_encounter() -> RoomData:
	var e := RoomData.new()
	e.enemy_spawns = [{"enemy_id": &"test_dummy", "position": Vector2(80.0, 0.0)}]
	e.party_spawns = [Vector2(-80.0, 0.0)]
	return e

func _battle():
	var view = in_tree(BattleScene.instantiate())
	view._ready()
	var config := RunConfig.new()
	config.seed = 1
	config.party = _make_party()
	view.begin_with_encounter(config, _make_encounter())
	return view

## The key a player presses, not the function under it.
func _escape(view) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	view._unhandled_input(key)

func test_escape_opens_the_menu_and_holds_the_fight() -> void:
	var view = _battle()
	assert_false(view._pause_menu.visible, "the menu starts closed")
	assert_false(view.paused)
	_escape(view)
	assert_true(view._pause_menu.visible, "escape must open the menu")
	assert_true(view.paused, "the fight must actually pause while the menu is open")
	view.free()

func test_escape_closes_the_menu_and_resumes_the_fight() -> void:
	var view = _battle()
	_escape(view)
	_escape(view)
	assert_false(view._pause_menu.visible, "escape must close the menu it opened")
	assert_false(view.paused, "closing the menu resumes the fight it held")
	view.free()

## The same rule the unit card follows: a pause the player took themselves is
## theirs, and closing an overlay must not hand it back.
func test_a_menu_over_an_already_paused_fight_leaves_it_paused() -> void:
	var view = _battle()
	view.set_paused(true)
	_escape(view)
	_escape(view)
	assert_true(view.paused, "the player paused this fight, not the menu")
	view.free()

func test_resume_closes_the_menu() -> void:
	var view = _battle()
	_escape(view)
	view._pause_menu.resume_pressed.emit()
	assert_false(view._pause_menu.visible)
	assert_false(view.paused)
	view.free()

## Issue 741 built plan staging so the popout could be opened DURING a fight,
## so the menu entry has to actually reach it.
func test_the_menu_opens_plans_and_equipment_over_the_held_fight() -> void:
	var view = _battle()
	_escape(view)
	view._pause_menu.plans_pressed.emit()
	assert_false(view._pause_menu.visible, "the menu gets out of the popout's way")
	assert_true(view._inspect_panel.visible, "Plans & Equipment must open")
	view.free()

## The two the issue warns must not be quietly dropped, plus the three it names.
func test_the_menu_carries_every_control_the_toolbar_had() -> void:
	var view = _battle()
	var labels: Array[String] = view._pause_menu.button_labels()
	for wanted in ["Resume", "Plans & Equipment", "Restart (same seed)", "Settings", "Change party"]:
		assert_true(labels.has(wanted), "the pause menu is missing '%s': it has %s" % [wanted, labels])
	view.free()

## `What to show` is display options and belongs under Settings.
func test_settings_opens_the_display_options() -> void:
	var view = _battle()
	_escape(view)
	assert_false(view._display_options.visible)
	view._pause_menu.settings_pressed.emit()
	assert_true(view._display_options.visible, "Settings must reach 'What to show'")
	view.free()

## The seed is the whole content of "Restart (same seed)", so it moved into the
## card with the button rather than off the screen.
func test_the_menu_names_the_party_the_room_and_the_seed() -> void:
	var view = _battle()
	for label in [view._party_label, view._encounter_label, view._seed_label]:
		assert_true(view._pause_menu.is_ancestor_of(label),
			"'%s' is not inside the pause menu" % label.text)
	assert_true(view._seed_label.text.begins_with("Seed "), view._seed_label.text)
	view.free()

## A menu over a resolved room would be a second answer to the question the end
## card is already asking.
func test_escape_does_nothing_over_the_end_card() -> void:
	var view = _battle()
	view._end_banner.visible = true
	_escape(view)
	assert_false(view._pause_menu.visible)
	view.free()

## Placement is not a fight, so there is nothing to hold.
func test_escape_does_nothing_during_placement() -> void:
	var view = _battle()
	view.setup = true
	_escape(view)
	assert_false(view._pause_menu.visible)
	view.free()
