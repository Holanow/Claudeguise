extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")
const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")

## Issue 378, part 1: nothing the arena draws may leave the arena rectangle.
## The playtester measured a Goblin Archer plate at y=168 against a top border
## at y=185, a Priest sprite up in the toolbar row, and a Siege Engine at
## y=550-645 against a bottom border at y=633.

const BOUNDS := UnitView.ARENA_BOUNDS


func _unit(id: int, pos: Vector2, name: String = "Goblin Archer") -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.position = pos
	u.hp = 5
	u.hp_max = 10
	u.alive = true
	u.display_name = name
	return u


func _corner() -> Vector2:
	return Vector2(CG.ARENA_HALF_WIDTH, -CG.ARENA_HALF_HEIGHT)


func test_into_arena_is_zero_for_something_already_inside() -> void:
	# The negative half. A rule that always fires is furniture.
	assert_eq(UnitView.into_arena(Rect2(-10.0, -10.0, 20.0, 20.0)), Vector2.ZERO)


func test_into_arena_pushes_a_rect_back_over_each_edge() -> void:
	assert_eq(UnitView.into_arena(Rect2(BOUNDS.position - Vector2(7.0, 0.0), Vector2(4.0, 4.0))),
		Vector2(7.0, 0.0), "over the left edge")
	assert_eq(UnitView.into_arena(Rect2(BOUNDS.position - Vector2(0.0, 9.0), Vector2(4.0, 4.0))),
		Vector2(0.0, 9.0), "over the top edge")
	assert_eq(UnitView.into_arena(Rect2(BOUNDS.end, Vector2(6.0, 3.0))),
		Vector2(-6.0, -3.0), "over the bottom right corner")


func test_a_body_at_the_edge_is_drawn_inside_it() -> void:
	# The Siege Engine case: the simulation clamps a unit's CENTRE and a body
	# has a radius, so the sprite hung 12 pixels past the bottom border.
	var u := _unit(0, _corner())
	u.radius = 22.0
	var at := UnitView.drawn_position(u, [u])
	var body := UnitView.drawn_box(UnitView.shape_id(u), u.team, UnitView.display_radius(u))
	var box := Rect2(at + body.position, body.size)
	assert_true(BOUNDS.encloses(box),
		"the drawn body %s must sit inside the arena %s" % [box, BOUNDS])
	assert_ne(at, u.position, "sanity: a unit in the corner really does have to be moved")


func test_a_name_plate_at_the_top_edge_stays_inside() -> void:
	# The plate hangs above the bar stack, so a unit pressed against the top
	# border is the case that put "Goblin Archer" on the page background.
	var u := _unit(0, Vector2(0.0, -CG.ARENA_HALF_HEIGHT))
	var chip := UnitView.plate_rect(u, [u])
	assert_true(BOUNDS.encloses(chip), "the plate %s must sit inside the arena %s" % [chip, BOUNDS])


func test_every_plate_of_a_full_top_row_stays_inside() -> void:
	# Ten units along the top edge: each one is clamped, and clamping alone
	# would pile them into the same row, which is what PLATE_ROWS' sideways
	# entries exist for.
	var units: Array = []
	for i in 10:
		units.append(_unit(i, Vector2(-400.0 + 90.0 * float(i), -CG.ARENA_HALF_HEIGHT)))
	for u in units:
		assert_true(BOUNDS.encloses(UnitView.plate_rect(u, units)),
			"%d's plate left the arena" % u.id)


func test_a_floater_stops_rising_at_the_ceiling() -> void:
	var floater := Node2D.new()
	floater.set_script(DamageFloaterScript)
	floater.position = Vector2(0.0, -CG.ARENA_HALF_HEIGHT + 4.0)
	floater.show_death("Abomination dies", Palette.TEXT, 24)
	# Stops one step short of the lifetime: past it `_process` frees itself and
	# returns before anything else runs.
	for i in 20:
		floater._process(0.1)
		assert_true(BOUNDS.encloses(floater.extent()),
			"a rising plate must not leave the arena at step %d: %s" % [i, floater.extent()])
	floater.free()


## Issue 378, part 3: damage floaters stagger by extent, as death plates do
## since #367. `22`, `2` and `2` stacked into one smear at (405-510, 355-395).

func _view_with_target(pos: Vector2) -> Node2D:
	var state := CombatState.new(1)
	var target := _unit(0, pos, "Abomination")
	target.team = CG.Team.PLAYER
	state.units.append(target)
	var view = in_tree(BattleScene.instantiate())
	view.state = state
	view.event_cursor = 0
	DisplayOptions.set_enabled(&"damage_numbers", true)
	return view


func _hit(view: Node2D, amount: int) -> void:
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.target_id = 0
	e.amount = amount
	e.amount_before_mitigation = amount
	view.state.emit(e)
	view.consume_events()


func test_three_numbers_on_one_unit_do_not_overlap() -> void:
	# The playtester's exact case, and the reason a point radius could not fix
	# it: `22` is nearly twice as wide as `2`, so the distance at which two of
	# them collide depends on what they say.
	var view := _view_with_target(Vector2.ZERO)
	for amount in [22, 2, 2]:
		_hit(view, amount)

	var boxes: Array[Rect2] = []
	for child in view.get_node("Arena").get_children():
		if child.get_script() == DamageFloaterScript:
			boxes.append(child.extent())
	assert_eq(boxes.size(), 3, "three hits, three numbers")
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			assert_false(boxes[i].intersects(boxes[j]),
				"%s and %s print through each other" % [boxes[i], boxes[j]])
	DisplayOptions.reset()


func test_a_lone_number_is_not_staggered_away_from_nothing() -> void:
	# The negative half again. A stagger that always fires would move every
	# number off the unit it belongs to.
	var view := _view_with_target(Vector2.ZERO)
	_hit(view, 7)
	var floater: Node2D = null
	for child in view.get_node("Arena").get_children():
		if child.get_script() == DamageFloaterScript:
			floater = child
	assert_eq(floater.position, Vector2.ZERO, "the first number of a fight sits on its target")
	DisplayOptions.reset()


func test_a_number_spawned_at_the_edge_lands_inside_the_arena() -> void:
	var view := _view_with_target(_corner())
	_hit(view, 22)
	for child in view.get_node("Arena").get_children():
		if child.get_script() == DamageFloaterScript:
			assert_true(BOUNDS.encloses(child.extent()),
				"a number spawned in the corner must not spawn outside: %s" % child.extent())
	DisplayOptions.reset()
