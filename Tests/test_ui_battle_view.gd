extends "res://Tests/TestCase.gd"


## BattleView reads CombatEvent, never polls CombatUnit for "what happened".

func _make_state_with_units() -> CombatState:
	var state := CombatState.new(1)
	var a := CombatUnit.new()
	a.id = 0
	a.team = CG.Team.PLAYER
	a.display_name = "Warrior"
	state.units.append(a)
	var b := CombatUnit.new()
	b.id = 1
	b.team = CG.Team.ENEMY
	b.display_name = "Rat"
	state.units.append(b)
	return state

func test_consume_events_advances_the_cursor() -> void:
	var state := _make_state_with_units()
	var view := BattleView.new()
	view.state = state
	view.event_cursor = 0

	state.emit(CombatEvent.make(CG.EventKind.FIGHT_START, 0))
	view.consume_events()
	assert_eq(view.event_cursor, 1)

	state.emit(CombatEvent.make(CG.EventKind.DAMAGE, 1))
	state.emit(CombatEvent.make(CG.EventKind.DAMAGE, 1))
	view.consume_events()
	assert_eq(view.event_cursor, 3)
	view.free()

func test_consume_events_does_not_reprocess_old_events() -> void:
	var state := _make_state_with_units()
	var view := BattleView.new()
	view.state = state
	view.event_cursor = 0

	for i in 3:
		state.emit(CombatEvent.make(CG.EventKind.DAMAGE, i))
	view.consume_events()
	assert_eq(view.event_cursor, 3)

	# No new events: cursor must not move or double-count.
	view.consume_events()
	assert_eq(view.event_cursor, 3)
	view.free()

## Issue 24: CombatLogView.line_for_event now drops a poison/burn tick's log
## line, and the two paths (log, floater) both read straight from the event
## in consume_events() -- neither calls the other. This is the check that the
## affliction really is "still visible somewhere" once the log stops saying
## it: the floater must fire from the event itself regardless of what the log
## chose to print, which is what makes dropping the line safe rather than
## just quieter.
func test_a_poison_shaped_damage_event_still_spawns_a_floater_though_the_log_drops_it() -> void:
	var state := _make_state_with_units()
	var view := BattleView.new()
	view.state = state
	view.event_cursor = 0
	view._arena = Node2D.new()

	# Issue 136 defaults the numbers off. Turned on here because this test is
	# specifically about a poison tick STILL producing a floater while the log
	# drops its line -- with them off it would pass by drawing nothing, which is
	# the opposite of what it was written to catch.
	DisplayOptions.set_enabled(&"damage_numbers", true)

	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = -1
	e.target_id = 1
	e.amount = 1
	e.amount_before_mitigation = 1
	e.status = CG.Status.POISON
	state.emit(e)
	view.consume_events()

	# 1 again since #573 deleted the impact ring. It was 2 while PR #69's
	# wiring spawned an ImpactFlash beside the floater; the floater is what
	# this test was written to check for and it is still there.
	assert_eq(view._arena.get_child_count(), 1,
		"a poison tick must still spawn a floating number even though the log line is dropped")
	DisplayOptions.reset()
	view._arena.free()
	view.free()

# ---------------------------------------------------------------------------
# Issue 187: the death and miss text.

const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")
const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")

func _view_with_arena() -> BattleView:
	var view := BattleView.new()
	view.state = _make_state_with_units()
	view.event_cursor = 0
	view._arena = Node2D.new()
	return view

func _last_marker(view) -> Node2D:
	var children: Array = view._arena.get_children()
	return children[children.size() - 1]

func _death_marker_for(view, unit_id: int) -> Node2D:
	var e := CombatEvent.make(CG.EventKind.DEATH, 1)
	e.target_id = unit_id
	view.state.emit(e)
	view.consume_events()
	return _last_marker(view)

## **A defect, not a taste call.** Every death was announced in
## `Palette.TEAM_ENEMY` regardless of who died, so **losing your own pawn was
## drawn in the enemy's colour** -- the same class of mistake as `HP_LOW` and
## `TEAM_ENEMY` being the same value on the health bars. Both sides asserted,
## because a single-sided check passes if every death is drawn in one colour.
func test_a_death_is_announced_in_the_colour_of_whoever_died() -> void:
	var view := _view_with_arena()
	var mine := _death_marker_for(view, 0)
	assert_eq(mine._color, Palette.TEAM_PLAYER, "a party pawn's death must not read as an enemy event")
	var theirs := _death_marker_for(view, 1)
	assert_eq(theirs._color, Palette.TEAM_ENEMY)
	assert_ne(mine._color, theirs._color, "the two sides' deaths must be distinguishable")
	view._arena.free()
	view.free()

## `Miss` was drawn at `FONT_SIZE_FLOATER` -- 34 before the display scale, so 51
## pixels across the arena, the same size as a damage number. A miss is the
## smallest event in the game and should be the quietest mark on the screen.
func test_miss_and_death_text_are_no_longer_damage_number_sized() -> void:
	var view := _view_with_arena()
	var floater_size := int(round(Palette.FONT_SIZE_FLOATER * UnitViewScript.DISPLAY_SCALE))

	var miss := CombatEvent.make(CG.EventKind.MISS, 1)
	miss.target_id = 1
	view.state.emit(miss)
	view.consume_events()
	var miss_marker := _last_marker(view)
	assert_true(miss_marker._font_size < floater_size,
		"Miss is drawn at %d, the damage-number size" % miss_marker._font_size)

	var death := _death_marker_for(view, 1)
	assert_true(death._font_size < floater_size,
		"death text is drawn at %d, the damage-number size" % death._font_size)

	# The text itself must survive being shrunk -- a mark nobody can read is not
	# an improvement on one that is too loud.
	assert_true(miss_marker._font_size >= Palette.FONT_SIZE_SMALL,
		"shrunk past legibility at %d" % miss_marker._font_size)
	assert_true(death._text.contains("Rat"), "a death still has to say who died")
	view._arena.free()
	view.free()
