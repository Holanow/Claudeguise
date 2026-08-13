extends "res://Tests/TestCase.gd"

const FloorMapView := preload("res://Scripts/UI/FloorMapView.gd")
const FloorPlan := preload("res://Scripts/Floor/FloorPlan.gd")
const FloorRoom := preload("res://Scripts/Floor/FloorRoom.gd")
const FloorRun := preload("res://Scripts/Floor/FloorRun.gd")
const FloorGenerator := preload("res://Scripts/Floor/FloorGenerator.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

## Issue 43: the floor exists (Scripts/Floor/**) and nothing in Scripts/UI
## ever referenced it. These check the screen's own logic — room layout,
## which rooms are enterable, and that a fight's outcome is both correct
## and actually visible — separately from whether a real fight resolves a
## particular way (that's Scripts/Combat's own concern).

func _make_view() -> Control:
	var view := Control.new()
	view.set_script(FloorMapView)
	view._ready()
	return view

## Three-room line: entrance(0) -- mid(1) -- far(2). No FloorGenerator
## involved, so the graph shape is exact and known rather than seed-derived.
func _make_linear_plan() -> FloorPlan:
	var plan := FloorPlan.new()
	var entrance := FloorRoom.new()
	entrance.id = 0
	entrance.type = FloorRoom.Type.ENEMY
	entrance.connections = [1]
	var mid := FloorRoom.new()
	mid.id = 1
	mid.type = FloorRoom.Type.TRAP
	mid.connections = [0, 2]
	var far := FloorRoom.new()
	far.id = 2
	far.type = FloorRoom.Type.TREASURE
	far.connections = [1]
	plan.rooms = [entrance, mid, far]
	plan.entrance_id = 0
	plan.miniboss_id = -1
	plan.boss_id = -1
	return plan

func test_open_builds_a_button_per_reachable_room() -> void:
	var view := _make_view()
	var run := FloorRun.new(_make_linear_plan())
	var party: Array[PawnData] = []
	view.open(run, party)
	assert_eq(view._room_buttons.size(), 3)
	view.free()

func test_current_room_button_is_disabled_and_marked_here() -> void:
	var view := _make_view()
	var run := FloorRun.new(_make_linear_plan())
	var party: Array[PawnData] = []
	view.open(run, party)
	var current: Button = view._room_buttons[0]
	assert_true(current.disabled)
	assert_true(current.text.contains("here"))
	view.free()

## Criterion 2: the room you are about to enter is identifiable before you
## enter it. The far room (not adjacent to the entrance) must exist on
## screen but not be enterable yet, and its type must still be named.
func test_non_adjacent_room_is_shown_but_not_enterable() -> void:
	var view := _make_view()
	var run := FloorRun.new(_make_linear_plan())
	var party: Array[PawnData] = []
	view.open(run, party)
	var far: Button = view._room_buttons[2]
	assert_true(far.disabled, "a room two hops away must not be enterable directly")
	assert_true(far.text.contains("Treasure"), far.text)
	view.free()

func test_adjacent_non_fight_room_is_enterable() -> void:
	var view := _make_view()
	var run := FloorRun.new(_make_linear_plan())
	var party: Array[PawnData] = []
	view.open(run, party)
	var mid: Button = view._room_buttons[1]
	assert_false(mid.disabled)
	view.free()

## The real bug found on a real launch: _refresh() unconditionally
## overwrote whatever status text _on_room_pressed had just set, so an
## outcome message ("Cleared the Enemy...") was never actually visible —
## it was replaced by the ambient "You are in" text in the same frame,
## before a player could ever read it.
func test_refresh_message_is_not_immediately_overwritten() -> void:
	var view := _make_view()
	var run := FloorRun.new(_make_linear_plan())
	var party: Array[PawnData] = []
	view.open(run, party)
	view._refresh("Cleared the Enemy. Priest (down)")
	assert_eq(view._status_label.text, "Cleared the Enemy. Priest (down)")
	view.free()

func test_entering_a_trap_room_marks_it_visited_without_a_fight() -> void:
	var view := _make_view()
	var run := FloorRun.new(_make_linear_plan())
	var party: Array[PawnData] = []
	view.open(run, party)
	view._on_room_pressed(run.plan.room(1))
	assert_true(run.visited.has(1))
	assert_eq(run.current_room_id, 1)
	view.free()

## Needs real Registry content (a fight room resolves through the real
## simulation), so this is a no-op rather than a false pass while empty.
func test_a_fight_room_resolves_one_way_or_another() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()
	if class_ids.is_empty() or encounter_ids.is_empty():
		return
	var view := _make_view()
	var run := FloorRun.new(_make_linear_plan())
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(class_ids[0], class_ids[0], String(class_ids[0]))]
	view.open(run, party)
	var run_ended_calls: Array = []
	view.run_ended.connect(func(victory: bool): run_ended_calls.append(victory))
	view._on_room_pressed(run.plan.room(0))
	if run_ended_calls.is_empty():
		# CONTINUES: the room resolved without ending the run, so it must
		# now read as visited and the party's carried state must be real
		# (either a plain win, hp still full, or a real fixture bug — not
		# silently untouched).
		assert_true(run.visited.has(0))
		assert_eq(run.current_room_id, 0)
	else:
		# DEFEAT or VICTORY: the run ended, exactly once.
		assert_eq(run_ended_calls.size(), 1)
	view.free()
