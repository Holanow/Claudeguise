extends "res://Tests/TestCase.gd"

## Issue 321: `Cultist dies` rendered as `ltist dies` because a health bar was
## drawn over the first three characters. Every unit view is a sibling in the
## arena, so a name drawn inside one view is under the bars of every view added
## after it.

const BattleScene := preload("res://Scenes/Battle.tscn")

## Past LABEL_HOLD_TICKS so no earlier test's hold decides what is up here.
const LATE := 200000

func _pawn(id: int, at: Vector2, name: String) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.position = at
	u.alive = true
	u.hp = 10
	u.hp_max = 10
	u.radius = 6.0
	u.team = CG.Team.ENEMY
	u.display_name = name
	u.current_action = &"goblin_swing"
	u.action_ticks_left = 5
	return u

## The scrum the playtester photographed: names close enough that the row
## search has to move them, which is what puts a plate over a neighbour.
func _scrum() -> CombatState:
	var state := CombatState.new(0)
	state.tick = LATE
	var names := ["Cultist", "Ghoul", "Goblin Archer", "Brute"]
	for i in names.size():
		state.units.append(_pawn(i, Vector2(0.0, float(i) * 14.0), names[i]))
	return state

## The defect is reachable at all: some plate lands on somebody else's bars.
## Without this the ordering test below could pass on a fight where nothing
## ever overlaps, and prove nothing.
func test_a_plate_lands_on_another_units_bars() -> void:
	DisplayOptions.set_enabled(&"name_plates", true)
	var state := _scrum()
	var layout := UnitView.plate_layout(state)
	var hits := 0
	for id in layout:
		var chip: Rect2 = layout[id]
		for u in state.units:
			if u.id == int(id):
				continue
			var bars := UnitView.bar_stack_rect(u, state.units)
			var hit := chip.intersection(bars)
			if hit.size.x > 0.0 and hit.size.y > 0.0:
				hits += 1
	assert_true(hits > 0,
		"no plate covers another unit's bars in this fixture, so it cannot test the order")
	DisplayOptions.reset()

## The fix, stated as the rule: everything that draws a word over the arena is
## drawn after everything that draws a bar. Order is child order -- nothing in
## this project sets z_index.
func test_arena_text_is_drawn_after_every_unit() -> void:
	var view = in_tree(BattleScene.instantiate())
	view.state = _scrum()
	view.event_cursor = 0
	view._rebuild_units()

	var arena: Node2D = view.get_node("Arena")
	assert_true(view._text_layer != null, "the arena has no text layer")
	assert_true(arena.get_children().find(view._unit_layer)
			< arena.get_children().find(view._text_layer),
		"every body and bar must be drawn before any name")
	for id in view._unit_views:
		assert_eq(view._unit_views[id].get_parent(), view._unit_layer,
			"unit %s is not in the layer under the names" % id)

## A summon's view is added mid-fight, after the layer already exists. That is
## exactly the case that reintroduces the defect if nothing lifts the layer.
func test_a_unit_added_mid_fight_still_draws_under_the_text() -> void:
	var view = in_tree(BattleScene.instantiate())
	view.state = _scrum()
	view.event_cursor = 0
	view._rebuild_units()

	view.state.units.append(_pawn(9, Vector2(30.0, 30.0), "Siege Engine"))
	view._ensure_unit_views()

	assert_eq(view._unit_views[9].get_parent(), view._unit_layer,
		"a summon's view was added over the names")

## A death marker is added to the arena after both layers, so it is over every
## body and every name -- which is the half of #321 the playtester photographed.
func test_a_death_marker_is_drawn_above_the_bars() -> void:
	DisplayOptions.reset()
	var view = in_tree(BattleScene.instantiate())
	view.state = _scrum()
	view.event_cursor = 0
	view._rebuild_units()

	var death := CombatEvent.make(CG.EventKind.DEATH, LATE)
	death.target_id = 0
	view.state.events.append(death)
	view.consume_events()

	var arena: Node2D = view.get_node("Arena")
	var markers := 0
	for child in arena.get_children():
		if child.get_script() == BattleView.DamageFloaterScript:
			markers += 1
			assert_true(arena.get_children().find(child)
					> arena.get_children().find(view._text_layer),
				"a death marker must be drawn over the bars, not under them")
	assert_eq(markers, 1, "the death event drew no marker")
