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
	var view = BattleScene.instantiate()
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
		assert_eq(boxes[i].text, DisplayOptions.OPTIONS[i].label)
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


func test_name_plates_are_off_by_default() -> void:
	_reset()
	assert_false(DisplayOptions.enabled(&"name_plates"),
		"plates default off: eight units in one scrum collide and the top plate wins")

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
