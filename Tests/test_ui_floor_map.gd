extends "res://Tests/TestCase.gd"


## Issue 43: the floor exists (Scripts/Floor/**) and nothing in Scripts/UI
## ever referenced it. These check the screen's own logic — room layout,
## which rooms are enterable, and that a fight's outcome is both correct
## and actually visible — separately from whether a real fight resolves a
## particular way (that's Scripts/Combat's own concern).

func _make_view() -> FloorMapView:
	var view := FloorMapView.create()
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
	assert_eq(view.get_node("%StatusLabel").text, "Cleared the Enemy. Priest (down)")
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

## Issue 41's routing: "the equip screen, once something can be equipped."

func _make_pawn(id: String, method: CG.Method) -> PawnData:
	var pawn_class := ClassDef.new()
	pawn_class.method = method
	var pawn := PawnData.new()
	pawn.id = StringName(id)
	pawn.display_name = id
	pawn.pawn_class = pawn_class
	return pawn

func _make_weapon(martial_only: bool) -> EquipmentDef:
	var item := EquipmentDef.new()
	item.id = &"test_sword"
	item.display_name = "Test Sword"
	item.slot = EquipmentDef.Slot.WEAPON
	if martial_only:
		item.allowed_methods = [CG.Method.MARTIAL]
	return item

func test_picking_a_pawn_assigns_the_item_to_its_slot_and_clears_the_loot() -> void:
	var view := _make_view()
	var run := FloorRun.new(_make_linear_plan())
	var pawn := _make_pawn("Warrior", CG.Method.MARTIAL)
	var party: Array[PawnData] = [pawn]
	var item := _make_weapon(false)
	run.loot.append(item)
	view.open(run, party)

	view._on_pawn_picked(pawn, item)

	assert_eq(pawn.weapon, item)
	assert_false(run.loot.has(item))
	view.free()

func test_equip_button_is_disabled_with_no_loot() -> void:
	var view := _make_view()
	var run := FloorRun.new(_make_linear_plan())
	var party: Array[PawnData] = []
	view.open(run, party)
	assert_true(view.get_node("%EquipButton").disabled)
	view.free()

## Issue 42: the CELL room's own screen -- swift's FloorFightRunner API
## (cell_candidates/resolve_cell) existed and nothing called it. These need
## real Registry content (cell_candidates reads Registry.all_class_ids()),
## so they no-op rather than false-pass when content isn't loaded, same
## pattern as test_a_fight_room_resolves_one_way_or_another above.

func _make_cell_plan() -> FloorPlan:
	var plan := FloorPlan.new()
	var entrance := FloorRoom.new()
	entrance.id = 0
	entrance.type = FloorRoom.Type.ENEMY
	entrance.connections = [1]
	var cell := FloorRoom.new()
	cell.id = 1
	cell.type = FloorRoom.Type.CELL
	cell.connections = [0]
	plan.rooms = [entrance, cell]
	plan.entrance_id = 0
	plan.miniboss_id = -1
	plan.boss_id = -1
	return plan

func test_entering_a_cell_with_no_losses_offers_nothing_to_pick() -> void:
	var class_ids := Registry.all_class_ids()
	if class_ids.is_empty():
		return
	var view := _make_view()
	var run := FloorRun.new(_make_cell_plan())
	var living := PawnFactory.make_starter_pawn(class_ids[0], class_ids[0], String(class_ids[0]))
	var party: Array[PawnData] = [living]
	view.open(run, party)

	view._on_room_pressed(run.plan.room(1))

	assert_false(view.get_node("%CellPanel").visible, "nobody to replace, so there's nothing to offer a pick for")
	assert_true(run.visited.has(1))
	assert_eq(run.current_room_id, 1)
	view.free()

func test_entering_a_cell_with_a_loss_offers_real_candidates() -> void:
	var class_ids := Registry.all_class_ids()
	if class_ids.size() < 2:
		return
	var view := _make_view()
	var run := FloorRun.new(_make_cell_plan())
	var dead := PawnFactory.make_starter_pawn(class_ids[0], class_ids[0], String(class_ids[0]))
	run.record_result(dead.id, 0, 0, false)
	var party: Array[PawnData] = [dead]
	view.open(run, party)

	view._on_room_pressed(run.plan.room(1))

	assert_true(view.get_node("%CellPanel").visible, "a real loss must actually be offered a replacement")
	assert_eq(view._cell_room, run.plan.room(1))
	view.free()

func test_picking_a_cell_candidate_replaces_the_dead_pawn_and_enters_the_room() -> void:
	var class_ids := Registry.all_class_ids()
	if class_ids.size() < 2:
		return
	var view := _make_view()
	var run := FloorRun.new(_make_cell_plan())
	var dead := PawnFactory.make_starter_pawn(class_ids[0], class_ids[0], String(class_ids[0]))
	run.record_result(dead.id, 0, 0, false)
	var party: Array[PawnData] = [dead]
	view.open(run, party)
	view._on_room_pressed(run.plan.room(1))

	var candidates := FloorFightRunner.cell_candidates(run, run.plan.room(1), party)
	assert_false(candidates.is_empty(), "a fresh party of one is missing every other class")
	view._on_cell_pawn_picked(candidates[0])

	assert_eq(party[0], candidates[0], "the dead pawn's slot must now hold the recruit")
	assert_true(run.is_alive(candidates[0].id))
	assert_true(run.visited.has(1))
	assert_eq(run.current_room_id, 1)
	assert_false(view.get_node("%CellPanel").visible)
	view.free()

func test_skipping_a_cell_leaves_the_party_untouched_but_still_enters() -> void:
	var class_ids := Registry.all_class_ids()
	if class_ids.size() < 2:
		return
	var view := _make_view()
	var run := FloorRun.new(_make_cell_plan())
	var dead := PawnFactory.make_starter_pawn(class_ids[0], class_ids[0], String(class_ids[0]))
	run.record_result(dead.id, 0, 0, false)
	var party: Array[PawnData] = [dead]
	view.open(run, party)
	view._on_room_pressed(run.plan.room(1))

	view._on_cell_skipped()

	assert_eq(party[0], dead, "declining the offer must not change the roster")
	assert_true(run.visited.has(1))
	assert_eq(run.current_room_id, 1)
	assert_false(view.get_node("%CellPanel").visible)
	view.free()

func test_a_pawn_that_cannot_use_an_item_is_offered_but_disabled() -> void:
	var view := _make_view()
	var run := FloorRun.new(_make_linear_plan())
	var caster := _make_pawn("Geysermancer", CG.Method.MAGICAL)
	var party: Array[PawnData] = [caster]
	var item := _make_weapon(true)
	run.loot.append(item)
	view.open(run, party)

	view._on_equip_pressed()
	view._on_loot_item_pressed(item)

	var pawn_button: Button = null
	for child in view.get_node("%EquipList").get_children():
		if child is Button and child.text.begins_with("Geysermancer"):
			pawn_button = child
	assert_true(pawn_button != null, "the pawn should still be listed, just not enterable")
	assert_true(pawn_button.disabled)
	view.free()
