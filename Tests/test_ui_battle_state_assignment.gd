extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 512. `_text_layer` was built only by `_rebuild_units`, which only
## `begin_with_encounter` calls, and `_process` called `_text_layer.sync`
## unguarded -- so a tool that drove the view by assigning `state` died every
## stepped frame before it rendered anything. It failed silently and produced a
## plausible wrong picture, which is worse than a crash and is the same shape
## #280 records.
##
## Every test here steps WHOLE ticks, so the render alpha lands at 0 and bodies
## are placed at the previous tick. Nothing below reads a position; anything
## added that does must step sub-tick, the way `Tools/InterpShot.gd` does.

func _party() -> Array[PawnData]:
	var party: Array[PawnData] = []
	var class_ids := ClassLibrary.all_ids()
	for i in mini(4, class_ids.size()):
		party.append(PawnFactory.make_starter_pawn(
			class_ids[i], StringName("p%d" % i), String(class_ids[i])))
	return party

func _view_driven_by_assignment():
	var view = in_tree(BattleScene.instantiate())
	view.state = CombatSim.build(_party(),
		RoomLibrary.get_room(RoomLibrary.all_ids()[0]), 7)
	view.event_cursor = 0
	return view

func test_assigning_state_directly_builds_the_text_layer() -> void:
	var view = _view_driven_by_assignment()
	view._process(CG.TICK_SECONDS)
	assert_not_null(view._text_layer,
		"a stepped frame left the text layer null, so `_text_layer.sync` killed the frame")

## The one that would have caught it. `_text_layer.sync` sits ahead of every
## hand-off to the arena, so on the unguarded version these stay empty while the
## unit views ahead of it are updated -- a picture of a live fight on stale
## ground, which is exactly what looked like a real result on #501.
func test_a_stepped_frame_reaches_the_arena_when_state_was_assigned() -> void:
	var view = _view_driven_by_assignment()
	var arena = view.get_node("Arena")
	assert_eq(arena.units.size(), 0, "the arena is meant to start with nothing to draw")
	view._process(CG.TICK_SECONDS)
	assert_eq(arena.units.size(), view.state.units.size(),
		"the frame died before it handed the arena its units")
	assert_true(view.state.tick > 0, "no tick was spent, so nothing was proved")

## The negative direction. Nothing above may pass by the view quietly declining
## to step: a view with no state must not build layers or spend a tick.
func test_a_view_with_no_state_builds_nothing() -> void:
	var view = in_tree(BattleScene.instantiate())
	view._process(CG.TICK_SECONDS)
	assert_eq(view._text_layer, null, "a view with no fight in it built a text layer anyway")

## `begin_with_encounter` must still be the ordinary way in, and the text layer
## must still be the LAST child of the arena or a body can be drawn over a name
## (issue 321).
func test_the_text_layer_stays_above_the_bodies() -> void:
	var view = _view_driven_by_assignment()
	view._process(CG.TICK_SECONDS)
	var arena = view.get_node("Arena")
	assert_true(arena.get_children().find(view._text_layer)
		> arena.get_children().find(view._unit_layer),
		"the names are drawn before the bodies, so a body can paint over one")
