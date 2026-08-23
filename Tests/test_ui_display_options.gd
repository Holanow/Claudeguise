extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")
const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")

## Issue 136: floating damage numbers become a toggle, defaulting to off.

func _reset() -> void:
	DisplayOptions.reset()

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

func _make_encounter() -> Encounter:
	var e := Encounter.new()
	e.enemy_spawns = [{"enemy_id": &"test_dummy", "position": Vector2(80.0, 0.0)}]
	e.party_spawns = [Vector2(-80.0, 0.0)]
	return e

func _view():
	var view = in_tree(BattleScene.instantiate())
	view._ready()
	var config := RunConfig.new()
	config.seed = 1
	config.party = _make_party()
	view.config = config
	view.state = CombatSim.build(config.party, _make_encounter(), config.seed)
	view.event_cursor = 0
	view._rebuild_units()
	return view

## Events are pushed through `consume_events`, the real path, rather than by
## calling `_spawn_floater` -- the guard has to be somewhere the game actually
## goes through, and a test that calls the private function proves only that the
## private function works.
func _feed(view, event: CombatEvent) -> void:
	view.state.events.append(event)
	view.consume_events()

func _floater_count(view) -> int:
	var n := 0
	for child in view._arena.get_children():
		if child.get_script() == DamageFloaterScript:
			n += 1
	return n

func _damage_event(view) -> CombatEvent:
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 0)
	e.source_id = view.state.units[1].id
	e.target_id = view.state.units[0].id
	e.amount = 12
	return e

# ---------------------------------------------------------------------------
# The default, which is the whole issue
# ---------------------------------------------------------------------------

func test_damage_numbers_are_off_until_a_player_turns_them_on() -> void:
	_reset()
	assert_false(DisplayOptions.enabled(&"damage_numbers"),
		"the shipped default must be off -- that is the entire issue")

## Through the real event path: a damage event must produce no floater while the
## option is off, and must produce one when it is on. Both directions, because
## "no floaters" also passes if floaters are broken outright.
func test_a_damage_event_draws_no_number_while_the_option_is_off() -> void:
	_reset()
	var view = _view()
	_feed(view, _damage_event(view))
	assert_eq(_floater_count(view), 0, "a damage number was drawn with the option off")

	DisplayOptions.set_enabled(&"damage_numbers", true)
	_feed(view, _damage_event(view))
	assert_eq(_floater_count(view), 1, "turning it on must bring the number back")
	_reset()
	view.free()

## The issue is explicit that this is *specifically* the damage numbers. Death
## and miss markers mark things a player has no other way to see at the moment
## they happen, and they share `DamageFloater`'s script -- so a guard put one
## level too high would silently take them with it, and nothing else would fail.
func test_death_and_miss_markers_survive_the_option_being_off() -> void:
	_reset()
	var view = _view()
	var death := CombatEvent.make(CG.EventKind.DEATH, 0)
	death.target_id = view.state.units[0].id
	_feed(view, death)
	assert_eq(_floater_count(view), 1, "a death marker must still be drawn")

	var miss := CombatEvent.make(CG.EventKind.MISS, 0)
	miss.source_id = view.state.units[1].id
	miss.target_id = view.state.units[0].id
	_feed(view, miss)
	assert_eq(_floater_count(view), 2, "a miss marker must still be drawn")
	_reset()
	view.free()

# ---------------------------------------------------------------------------
# The place the fifth toggle will live
# ---------------------------------------------------------------------------

## Every option needs a label and a sentence. The same report that asked for
## less on screen also found that **nothing anywhere explains anything** -- no
## legend, no tooltip, no key -- so a toggle shipping without an explanation
## repeats the defect while claiming to fix it.
func test_every_option_carries_a_label_and_an_explanation() -> void:
	assert_true(DisplayOptions.OPTIONS.size() > 0, "the list must not be empty")
	for option in DisplayOptions.OPTIONS:
		assert_true(option.has("id") and option.id != &"", "every option needs an id")
		assert_false(String(option.get("label", "")).is_empty(),
			"option '%s' has no label" % option.id)
		assert_true(String(option.get("help", "")).length() > 20,
			"option '%s' needs a sentence explaining it, not a word" % option.id)
		assert_true(option.has("default"), "option '%s' must state its default" % option.id)

## The panel builds itself from the list, so adding an option cannot leave it
## unreachable -- the built-and-unreachable failure this project has hit eleven
## times, pre-empted for the toggles specifically.
func test_the_panel_shows_a_checkbox_for_every_option() -> void:
	_reset()
	var panel := Control.new()
	panel.set_script(DisplayOptionsPanel)
	panel._ready()
	var boxes: Array[CheckBox] = []
	for n in _all(panel):
		if n is CheckBox:
			boxes.append(n)
	assert_eq(boxes.size(), DisplayOptions.OPTIONS.size(), "one checkbox per option")
	for i in DisplayOptions.OPTIONS.size():
		## `begins_with` rather than equality since issue 323: the row carries
		## its own state after the label. A missing, mislabelled or reordered
		## row still fails here.
		assert_true(boxes[i].text.begins_with(DisplayOptions.OPTIONS[i].label),
			"row %d reads '%s'" % [i, boxes[i].text])
	panel.free()

## Driven through the control a player touches, not through `set_enabled`.
func test_ticking_the_box_changes_what_the_game_draws() -> void:
	_reset()
	var panel := Control.new()
	panel.set_script(DisplayOptionsPanel)
	panel._ready()
	var box: CheckBox = null
	for n in _all(panel):
		if n is CheckBox:
			box = n
			break
	assert_true(box != null)
	assert_false(DisplayOptions.enabled(&"damage_numbers"))
	box.button_pressed = true
	assert_true(DisplayOptions.enabled(&"damage_numbers"),
		"pressing the checkbox must change the option, not just the checkbox")
	_reset()
	panel.free()

## The state is static so it survives a screen being rebuilt between fights --
## a preference that resets every time you press Restart is not a preference.
## Which means a freshly built panel must re-read it rather than show defaults.
func test_a_rebuilt_panel_shows_the_choice_rather_than_the_default() -> void:
	_reset()
	DisplayOptions.set_enabled(&"damage_numbers", true)
	var panel := Control.new()
	panel.set_script(DisplayOptionsPanel)
	panel._ready()
	panel.refresh()
	for n in _all(panel):
		if n is CheckBox:
			assert_true(n.button_pressed, "the box must show the choice already made")
			break
	_reset()
	panel.free()

func test_reset_returns_every_option_to_its_shipped_default() -> void:
	DisplayOptions.set_enabled(&"damage_numbers", true)
	DisplayOptions.reset()
	for option in DisplayOptions.OPTIONS:
		assert_eq(DisplayOptions.enabled(option.id), option.default,
			"'%s' did not come back to its default" % option.id)

func _all(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all(c))
	return out

# ---------------------------------------------------------------------------
# Issue 82: name plates become the second toggle
# ---------------------------------------------------------------------------


## Issue 440: both of these ship off. A blind tester on the old defaults could
## not see fight 1 at all, and turning plates off made it legible.
func test_name_plates_are_off_by_default() -> void:
	_reset()
	assert_false(DisplayOptions.enabled(&"name_plates"),
		"plates default off: on-by-default hid the fight for every blind tester who met it")

func test_ground_ticks_are_off_in_the_log_by_default() -> void:
	_reset()
	assert_false(DisplayOptions.enabled(&"log_hazard_ticks"),
		"ground ticks default off: 141 of 402 lines in a Burn Pit fight buried every death")

## The rule that decides *when* a plate would show -- focused or winding up,
## plus a hold because that trigger flickers several times a second -- must
## survive the toggle. It is a third state somebody may want, and implementing
## "off" by deleting it would throw away the harder half.
func test_the_label_activity_rule_survives_the_toggle() -> void:
	_reset()
	var state := CombatState.new(0)
	var a := CombatUnit.new()
	a.id = 0
	a.hp = 10
	a.hp_max = 10
	a.display_name = "A"
	var b := CombatUnit.new()
	b.id = 1
	b.hp = 10
	b.hp_max = 10
	b.display_name = "B"
	b.team = CG.Team.ENEMY
	state.units.append(a)
	state.units.append(b)

	# An ENEMY that is idle and unfocused: nothing to say about it. Party units
	# are always named by this rule, so they cannot show the negative half.
	assert_false(UnitView.should_show_label(b, state.units),
		"an idle, unfocused enemy has no reason to be named")
	# Focused by someone: the trigger the hold exists to smooth.
	a.focus_id = b.id
	assert_true(UnitView.should_show_label(b, state.units),
		"the activity rule must still fire -- it is not deleted, only gated")

# ---------------------------------------------------------------------------
# Issue 323: the toggles could be clicked all along, and nobody could see it
# ---------------------------------------------------------------------------
#
# Measured against the rendered panel: the engine's tick is a 14x14 block at
# RGB(22,22,25) on a panel of RGB(20,19,26). Two points of luminance, and no
# tint can lift it because the icon art is itself dark. So the row says what it
# is doing in words, and looks like the other controls on the screen.

func test_a_row_says_whether_the_option_is_showing_or_hidden() -> void:
	_reset()
	var panel := Control.new()
	panel.set_script(DisplayOptionsPanel)
	panel._ready()
	var boxes: Array[CheckBox] = []
	for n in _all(panel):
		if n is CheckBox:
			boxes.append(n)

	for i in DisplayOptions.OPTIONS.size():
		var option = DisplayOptions.OPTIONS[i]
		var off_text: String = boxes[i].text
		assert_true(off_text.contains("hidden") != off_text.contains("showing"),
			"a row says one of the two and not both: %s" % off_text)
		assert_eq(off_text.contains("showing"), bool(option.default),
			"row %d must read the state it is actually in: %s" % [i, off_text])

		## Through the control, not through `set_enabled`.
		boxes[i].button_pressed = not boxes[i].button_pressed
		assert_ne(boxes[i].text, off_text, "the words must change with the option")
		assert_eq(boxes[i].text.contains("showing"), DisplayOptions.enabled(option.id),
			"the words and the option must agree: %s" % boxes[i].text)
	_reset()
	panel.free()

## The pair the one above needs: a panel rebuilt on a choice already made must
## open reading that choice, not the default.
func test_a_rebuilt_panel_reads_the_choice_in_words() -> void:
	_reset()
	DisplayOptions.set_enabled(&"damage_numbers", true)
	var panel := Control.new()
	panel.set_script(DisplayOptionsPanel)
	panel._ready()
	panel.refresh()
	for n in _all(panel):
		if n is CheckBox:
			assert_true(n.text.contains("showing"), n.text)
			break
	_reset()
	panel.free()

## The row must not depend on the engine's dark-on-dark tick to look like a
## control. Asserted as contrast against the panel it sits on, which is the
## property that failed, rather than as "a stylebox exists".
func test_every_row_is_visible_against_the_panel_behind_it() -> void:
	_reset()
	var panel := Control.new()
	panel.set_script(DisplayOptionsPanel)
	panel._ready()
	var seen := 0
	for n in _all(panel):
		if not (n is CheckBox):
			continue
		seen += 1
		## Every state, not just the resting one: a ticked row under the pointer
		## draws `hover_pressed`, and that one was missed until a screenshot
		## showed the outline gone.
		for state in DisplayOptionsPanel.ROW_STATES:
			var style: StyleBox = n.get_theme_stylebox(StringName(state))
			assert_true(style is StyleBoxFlat, "row %s has no filled %s" % [n.text, state])
			var lift: float = _luminance(style.bg_color) - _luminance(Palette.BACKGROUND)
			assert_true(lift > 0.02,
				"%s '%s' is %.4f over the panel, which is what nobody could see" % [
					state, n.text, lift])
	assert_eq(seen, DisplayOptions.OPTIONS.size(), "every row was checked")
	panel.free()

## And the negative: the check above must be able to fail. The engine's own
## default for this control is exactly the thing it is guarding against.
func test_the_contrast_check_would_catch_the_engine_default() -> void:
	var bare := CheckBox.new()
	var style: StyleBox = bare.get_theme_stylebox(&"normal")
	var lift := 0.0 if not (style is StyleBoxFlat) else _luminance(style.bg_color) - _luminance(Palette.BACKGROUND)
	assert_false(lift > 0.02,
		"an unstyled CheckBox must not pass the check the styled ones have to")
	bare.free()

static func _luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

## Issue 319 added two options and four of them do not fit 720px, let alone the
## 844x390 launch this panel has run off the bottom of before. Both directions:
## it must not grow past the room it is given, and it must not shrink below one
## row when the room is absurd.
func test_the_panel_never_grows_past_the_screen_it_is_on() -> void:
	_reset()
	var panel := Control.new()
	panel.set_script(DisplayOptionsPanel)
	panel._ready()
	assert_true(DisplayOptions.OPTIONS.size() >= 4,
		"this check is about a list long enough to overflow")

	panel.fit_within(300.0)
	assert_true(panel._scroll.custom_minimum_size.y <= 300.0,
		"asked for 300 and took %.1f" % panel._scroll.custom_minimum_size.y)
	panel.fit_within(0.0)
	assert_true(panel._scroll.custom_minimum_size.y >= Palette.TOUCH_TARGET_MIN,
		"a panel with no room must still show a row rather than vanish")

	## And with room to spare it stops at its own content rather than stretching.
	panel.fit_within(100000.0)
	assert_true(panel._scroll.custom_minimum_size.y < 100000.0,
		"the panel must not stretch to fill a screen it does not need")
	panel.free()

## Issue 396: the panel ran 34px past the bottom of a 720px window and lost its
## border and its last line, because `room` was spent entirely on the scroll
## and none of it on the margin and border around it.
func test_the_panel_leaves_room_for_its_own_border() -> void:
	_reset()
	var panel := Control.new()
	panel.set_script(DisplayOptionsPanel)
	panel._ready()
	panel.fit_within(500.0)
	assert_true(panel._scroll.custom_minimum_size.y <= 500.0 - DisplayOptionsPanel.CHROME_HEIGHT,
		"the whole panel is scroll plus chrome, and 500 is the room for the whole panel")
	panel.free()
