extends "res://Tests/TestCase.gd"

## Issue 378's second regime, which three-tick sampling never reached: the row
## search runs against every ALIVE unit, but only a fraction of those names are
## drawn. `Tools/PlateDensity.gd` measured 1594 plate-ticks on the last row over
## 3469 ticks of the six pickable rooms.

func _small(id: int, pos: Vector2, name: String = "Goblin Archer") -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.position = pos
	u.alive = true
	u.hp = 10
	u.hp_max = 10
	u.radius = 6.0
	u.team = CG.Team.ENEMY
	u.display_name = name
	return u

## Far enough past LABEL_HOLD_TICKS that no earlier test's hold is still up:
## `_hold_tick` is static and outlives one test.
const LATE := 100000

func _state(units: Array) -> CombatState:
	var state := CombatState.new(0)
	state.tick = LATE
	for u in units:
		state.units.append(u)
	return state

func _visible(u: CombatUnit) -> CombatUnit:
	u.current_action = &"goblin_swing"
	u.action_ticks_left = 5
	return u

# ---------------------------------------------------------------------------
# A name nobody can see must not take a row from one somebody can.
# ---------------------------------------------------------------------------

func test_a_hidden_plate_does_not_reserve_a_row() -> void:
	var quiet := _small(0, Vector2.ZERO)
	var busy := _visible(_small(1, Vector2(20.0, 0.0)))
	var units := [quiet, busy]
	var state := _state(units)

	assert_false(UnitView.should_show_label(quiet, units), "sanity: this name is not drawn")
	assert_eq(int(UnitView.plate_ranks(units).get(busy.id, -1)), 1,
		"sanity: without the state the hidden plate still takes row 0 and pushes this one up")
	assert_eq(int(UnitView.plate_ranks(units, state).get(busy.id, -1)), 0,
		"the only name on screen must sit on its own unit")

func test_a_hidden_plate_is_not_laid_out_at_all() -> void:
	var quiet := _small(0, Vector2.ZERO)
	var busy := _visible(_small(1, Vector2(20.0, 0.0)))
	var state := _state([quiet, busy])
	var layout := UnitView.plate_layout(state)
	assert_false(layout.has(quiet.id), "a name that is not drawn has no chip")
	assert_true(layout.has(busy.id))

func test_visible_plates_still_move_off_each_other() -> void:
	var a := _visible(_small(0, Vector2.ZERO))
	var b := _visible(_small(1, Vector2(20.0, 0.0)))
	var units := [a, b]
	var state := _state(units)
	var layout := UnitView.plate_layout(state)
	assert_false((layout[a.id] as Rect2).intersects(layout[b.id]),
		"two names that are both up must not share a pixel")

# ---------------------------------------------------------------------------
# Row exhaustion. Sixteen rows, and a scrum can want more.
# ---------------------------------------------------------------------------

## The old search stopped at `PLATE_ROWS.size() - 1` and placed there whatever
## the overlap, so every plate past the sixteenth piled onto the same last row.
## The least-overlap fallback has to beat that, and this is the fixture where
## the two differ.
func test_past_the_last_row_the_least_bad_row_wins_not_the_last_one() -> void:
	var units: Array = []
	for i in 24:
		units.append(_visible(_small(i, Vector2(float(i) * 4.0, 0.0))))
	var state := _state(units)
	var ranks := UnitView.plate_ranks(units, state)
	assert_eq(ranks.size(), 24, "sanity: every one of these names is up")

	var last := UnitView.PLATE_ROWS.size() - 1
	var on_last := 0
	for id in ranks:
		if int(ranks[id]) == last:
			on_last += 1
	assert_true(on_last < 8, "the overflow must spread over the rows, not pile onto the last one (got %d)" % on_last)

func test_the_row_chosen_is_never_worse_than_another_row_available_to_it() -> void:
	var units: Array = []
	for i in 24:
		units.append(_visible(_small(i, Vector2(float(i) * 4.0, 0.0))))
	var state := _state(units)
	var ranks := UnitView.plate_ranks(units, state)

	var placed: Array[Rect2] = []
	var sorted_ids: Array = ranks.keys()
	sorted_ids.sort()
	for id in sorted_ids:
		var u: CombatUnit = units[id]
		var chosen := UnitView.plate_rect(u, units, int(ranks[id]))
		var chosen_area := UnitView._overlap_area(chosen, placed)
		for row in UnitView.PLATE_ROWS.size():
			var area := UnitView._overlap_area(UnitView.plate_rect(u, units, row), placed)
			assert_true(chosen_area <= area,
				"unit %d took a row losing %.0f px2 when row %d loses %.0f" % [id, chosen_area, row, area])
		placed.append(chosen)
