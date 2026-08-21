extends "res://Tests/TestCase.gd"

## Issue 440: a relocated plate names the pawn it is standing over, not its own.
## Measured over 24,735 drawn plate-ticks of the six pickable rooms, a plate
## reads as the wrong pawn 45.7% of the time and as nobody 10.5%.

## Far enough past LABEL_HOLD_TICKS that no earlier test's hold is still up.
const LATE := 200000

func _pawn(id: int, pos: Vector2, name: String) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.position = pos
	u.alive = true
	u.hp = 10
	u.hp_max = 10
	u.radius = 6.0
	u.team = CG.Team.ENEMY
	u.display_name = name
	u.current_action = &"goblin_swing"
	u.action_ticks_left = 5
	return u

## Four names in one column, close enough that the row search must move three
## of them. This is the regime the playtester photographed.
func _scrum() -> CombatState:
	var state := CombatState.new(0)
	state.tick = LATE
	var names := ["Abomination", "Priest", "Geysermancer", "Siege Master"]
	for i in names.size():
		state.units.append(_pawn(i, Vector2(0.0, float(i) * 14.0), names[i]))
	return state

func _nearest_unit(state: CombatState, point: Vector2) -> CombatUnit:
	var best: CombatUnit = null
	var best_d := INF
	for u in state.units:
		var d: float = point.distance_to(UnitView.drawn_position(u, state.units))
		if d < best_d:
			best_d = d
			best = u
	return best

# ---------------------------------------------------------------------------
# The fixture has to reproduce the defect, or the test below proves nothing.
# ---------------------------------------------------------------------------

func test_the_scrum_really_does_put_a_chip_over_the_wrong_pawn() -> void:
	var state := _scrum()
	var layout := UnitView.plate_layout(state)
	var wrong := 0
	for u in state.units:
		if not layout.has(u.id):
			continue
		if _nearest_unit(state, (layout[u.id] as Rect2).get_center()).id != u.id:
			wrong += 1
	assert_true(wrong > 0,
		"the fixture is supposed to misplace at least one chip; it misplaced %d of %d" % [
			wrong, state.units.size()])

# ---------------------------------------------------------------------------
# The tether, which is what makes the name findable anyway.
# ---------------------------------------------------------------------------

## The endpoint is on the owner's own column and above its own bars, whatever
## the chip did. Not "nearest to its owner": in a scrum the anchor of one pawn
## can sit closer to a neighbour's centre than to its own, which is the whole
## reason proximity is not a usable cue and a line is.
func test_every_tether_ends_on_its_own_pawn() -> void:
	var state := _scrum()
	var layout := UnitView.plate_layout(state)
	for u in state.units:
		if not layout.has(u.id):
			continue
		var points := UnitView.plate_tether(u, state.units, layout[u.id])
		var own := UnitView.drawn_position(u, state.units)
		assert_almost_eq(points[1].x, own.x, 0.001,
			"\"%s\"'s tether does not end on its own column" % u.display_name)
		assert_almost_eq(points[1].y, own.y + UnitView.bar_stack_top(u), 0.001,
			"\"%s\"'s tether does not end at the top of its own bars" % u.display_name)

## Four anchors, four places. A tether that ends somewhere shared by two pawns
## would pass the test above and still name nothing.
func test_no_two_tethers_end_in_the_same_place() -> void:
	var state := _scrum()
	var layout := UnitView.plate_layout(state)
	var ends := {}
	for u in state.units:
		if not layout.has(u.id):
			continue
		var points := UnitView.plate_tether(u, state.units, layout[u.id])
		var key := "%.1f,%.1f" % [points[1].x, points[1].y]
		assert_false(ends.has(key),
			"\"%s\" and \"%s\" tether to the same point" % [u.display_name, ends.get(key, "")])
		ends[key] = u.display_name

func test_a_tether_starts_on_its_own_plate() -> void:
	var state := _scrum()
	var layout := UnitView.plate_layout(state)
	for u in state.units:
		if not layout.has(u.id):
			continue
		var chip: Rect2 = layout[u.id]
		var points := UnitView.plate_tether(u, state.units, chip)
		assert_almost_eq(points[0].x, chip.get_center().x, 0.001,
			"\"%s\"'s tether does not start under the middle of its plate" % u.display_name)
		assert_almost_eq(points[0].y, chip.end.y, 0.001,
			"\"%s\"'s tether does not start on its plate's bottom edge" % u.display_name)

## The gap the plate hangs across: the tether has to cross it, or it is a line
## from a plate to itself and ties nothing to anything.
func test_a_moved_plate_gets_a_tether_with_length_in_it() -> void:
	var state := _scrum()
	var layout := UnitView.plate_layout(state)
	var longest := 0.0
	for u in state.units:
		if not layout.has(u.id):
			continue
		var points := UnitView.plate_tether(u, state.units, layout[u.id])
		longest = maxf(longest, points[0].distance_to(points[1]))
	assert_true(longest > 20.0,
		"the longest tether in a four-deep scrum is %.1f px, which draws nothing" % longest)

## `bar_stack_top` is read back out of `label_baseline`, so the tether cannot
## drift from the plate it is measured against.
func test_the_tether_ends_where_the_bars_end() -> void:
	var u := _pawn(0, Vector2.ZERO, "Goblin")
	assert_true(UnitView.bar_stack_top(u) > UnitView.label_baseline(u),
		"the bars sit below the name's baseline, so the stack top must be the larger y")
	assert_true(UnitView.bar_stack_top(u) < 0.0,
		"the bar stack sits above the body's centre")
