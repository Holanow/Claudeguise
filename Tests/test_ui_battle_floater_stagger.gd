extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 26 item 3: in a scrum, several floating numbers used to spawn at the
## literal same point and read as one garbled string
## (Tools/preview/fight_04.png: "Cultist dies", a floating 2 and a unit label
## all on the same pixels). Each new floater near an existing one now spreads
## a step further rather than landing on top of it.

func _make_view_with_target(pos: Vector2) -> Node2D:
	var state := CombatState.new(1)
	var target := CombatUnit.new()
	target.id = 0
	target.team = CG.Team.PLAYER
	target.display_name = "Rat"
	target.position = pos
	state.units.append(target)

	var view = BattleScene.instantiate()
	view._ready()
	view.state = state
	view.event_cursor = 0
	DisplayOptions.set_enabled(&"damage_numbers", true)
	return view

func test_no_stagger_with_nothing_nearby() -> void:
	var view := _make_view_with_target(Vector2.ZERO)
	assert_eq(view._floater_stagger_offset(Vector2.ZERO), Vector2.ZERO)
	DisplayOptions.reset()
	view.free()

func test_each_additional_nearby_floater_spreads_further() -> void:
	var view := _make_view_with_target(Vector2.ZERO)

	var e1 := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e1.target_id = 0
	e1.amount = 5
	e1.amount_before_mitigation = 5
	view.state.emit(e1)
	view.consume_events()
	var offset_after_one: Vector2 = view._floater_stagger_offset(Vector2.ZERO)
	assert_ne(offset_after_one, Vector2.ZERO, "a second floater near the first must not land on it")

	var e2 := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e2.target_id = 0
	e2.amount = 3
	e2.amount_before_mitigation = 3
	view.state.emit(e2)
	view.consume_events()
	var offset_after_two: Vector2 = view._floater_stagger_offset(Vector2.ZERO)
	assert_ne(offset_after_two, offset_after_one,
		"a third floater must not land on either of the first two")
	assert_ne(offset_after_two, Vector2.ZERO)
	DisplayOptions.reset()
	view.free()

func test_a_death_marker_stays_within_the_stagger_budget() -> void:
	# The death marker's own vertical offset stacks on top of the
	# horizontal stagger, not instead of it: a killing blow's DAMAGE event
	# and its DEATH event fire the same tick and must not overlap either.
	const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")
	var view := _make_view_with_target(Vector2(50.0, 50.0))
	var damage := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	damage.target_id = 0
	damage.amount = 7
	damage.amount_before_mitigation = 7
	view.state.emit(damage)
	view.consume_events()

	var arena := view.get_node("Arena")
	var floater_x: float = _last_with_script(arena, DamageFloaterScript).position.x

	var death := CombatEvent.make(CG.EventKind.DEATH, 1)
	death.target_id = 0
	view.state.emit(death)
	view.consume_events()
	var marker_x: float = _last_with_script(arena, DamageFloaterScript).position.x

	assert_ne(floater_x, marker_x, "the death marker must not land on the same x as the damage floater it follows")
	DisplayOptions.reset()
	view.free()

## Issue 320: three "Rat dies" markers and a "Miss" inside a 130x100 box, two
## of them overlapping exactly. `_floater_stagger_offset` compares two points
## and the thing that collides is a plate as wide as the pawn's name, so three
## rats a point-radius apart each got a zero offset and printed on top of each
## other. Deaths now stack into a column.
func test_deaths_in_one_scrum_stack_instead_of_overprinting() -> void:
	const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")
	var view := _make_view_with_target(Vector2(200.0, 200.0))
	for i in 2:
		var extra := CombatUnit.new()
		extra.id = i + 1
		extra.team = CG.Team.ENEMY
		extra.display_name = "Rat"
		# Far enough apart that the point-radius stagger sees nothing, which is
		# exactly the case the playtester photographed.
		extra.position = Vector2(200.0 + 70.0 * float(i + 1), 200.0)
		view.state.units.append(extra)

	var arena := view.get_node("Arena")
	var ys: Array[float] = []
	for id in [0, 1, 2]:
		var death := CombatEvent.make(CG.EventKind.DEATH, 1)
		death.target_id = id
		view.state.emit(death)
		view.consume_events()
		var marker: Node2D = _last_with_script(arena, DamageFloaterScript)
		assert_true(marker.death_marker, "a death must spawn a death marker, not a plain floater")
		ys.append(marker.position.y)

	assert_ne(ys[0], ys[1], "the second death in a scrum must not print on the first")
	assert_ne(ys[1], ys[2], "nor the third on the second")
	assert_ne(ys[0], ys[2])
	DisplayOptions.reset()
	view.free()

## The negative half: a death across the arena from another one must not be
## dragged up into a column with it.
func test_a_death_far_from_another_does_not_stack() -> void:
	var view := _make_view_with_target(Vector2.ZERO)
	var far := CombatUnit.new()
	far.id = 1
	far.team = CG.Team.ENEMY
	far.display_name = "Goblin"
	far.position = Vector2(900.0, 0.0)
	view.state.units.append(far)
	assert_eq(view._death_stack_offset(far.position), Vector2.ZERO)

	var death := CombatEvent.make(CG.EventKind.DEATH, 1)
	death.target_id = 0
	view.state.emit(death)
	view.consume_events()
	assert_eq(view._death_stack_offset(far.position), Vector2.ZERO,
		"a death at the other end of the arena is not in this scrum")
	DisplayOptions.reset()
	view.free()

func _last_with_script(arena: Node, script: Script) -> Node2D:
	for i in range(arena.get_child_count() - 1, -1, -1):
		var child := arena.get_child(i)
		if child.get_script() == script:
			return child
	return null
