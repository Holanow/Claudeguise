extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 501: the simulation moves 15 times a second and the display draws 60.
## Without a render alpha three of every four frames are a repeat and the fourth
## is a jump, which is the flatness #500 names.

const FRAMES_PER_TICK := 4

func _walker() -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.display_name = "Walker"
	u.hp_max = 100
	u.hp = 100
	u.move_speed = 6.0
	u.position = Vector2(-400.0, 0.0)
	return u

## Alive, still, and far enough that the walker never arrives: once `outcome`
## is set `_process` returns immediately and would prove nothing.
func _quarry() -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 1
	u.team = CG.Team.ENEMY
	u.display_name = "Quarry"
	u.hp_max = 5000
	u.hp = 5000
	u.move_speed = 0.0
	u.position = Vector2(400.0, 0.0)
	return u

func _fight() -> Array:
	var state := CombatState.new(11)
	state.units.append(_walker())
	state.units.append(_quarry())
	var view = in_tree(BattleScene.instantiate())
	view._ready()
	view.state = state
	view.event_cursor = 0
	view._rebuild_units()
	view._curr_drawn = view._drawn_snapshot()
	return [view, state]

## Four rendered frames to the tick, the ratio a 60Hz display has against a
## 15Hz simulation.
func _frames(view, count: int) -> Array:
	var seen := []
	for i in count:
		# Re-stated every frame: `_decide_phase` skips a unit that already has
		# one, so this is a plan's output without needing a plan.
		view.state.unit(0).intent = Intent.move_to(Vector2(400.0, 0.0))
		view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))
		seen.append(view._unit_views[0].position)
	return seen

func _distinct(points: Array) -> int:
	var seen := {}
	for p in points:
		seen[p] = true
	return seen.size()

func test_every_rendered_frame_moves_a_walking_body() -> void:
	var pair := _fight()
	var view = pair[0]
	# Two ticks of lead-in, so the fight is walking rather than deciding.
	_frames(view, FRAMES_PER_TICK * 2)

	var seen := _frames(view, 8)
	assert_eq(_distinct(seen), 8,
		"eight consecutive frames of a walking pawn must be eight positions, not two")
	view.free()

## The negative half, and it is the one that fails loudly if the alpha is ever
## wired to something other than the leftover accumulator: a still pawn must
## not be given motion it never had.
func test_a_body_that_did_not_move_is_drawn_in_one_place() -> void:
	var pair := _fight()
	var view = pair[0]
	_frames(view, FRAMES_PER_TICK * 2)

	var quarry_seen := []
	for i in 8:
		_frames(view, 1)
		quarry_seen.append(view._unit_views[1].position)
	assert_eq(_distinct(quarry_seen), 1, "a unit with move_speed 0 must not drift")
	view.free()

func test_a_jump_further_than_a_walk_is_not_slid_through() -> void:
	var pair := _fight()
	var view = pair[0]
	var state: CombatState = pair[1]
	var far := state.unit(0).position + Vector2(500.0, 0.0)

	view._prev_drawn = {0: state.unit(0).position}
	assert_eq(view._tween_body(0, far, 0.5), far,
		"a teleport must be drawn where it lands, not halfway across the arena")
	view.free()

func test_a_shot_in_flight_is_drawn_between_the_two_ticks() -> void:
	var pair := _fight()
	var view = pair[0]
	var state: CombatState = pair[1]
	var p := Projectile.new()
	p.id = 3
	p.origin = Vector2(-100.0, 0.0)
	p.position = Vector2(100.0, 0.0)
	state.projectiles.append(p)
	view._prev_shots = {3: Vector2(-100.0, 0.0)}

	view._render(0.5, false)
	assert_eq(view._arena.shot_positions.get(3), Vector2(0.0, 0.0),
		"half a tick after launch, a shot is drawn half way")
	view.free()

## A shot the view has never seen before must appear where it is, or every
## projectile flies in from wherever the previous one happened to be.
func test_a_shot_with_no_previous_tick_is_drawn_where_it_is() -> void:
	var pair := _fight()
	var view = pair[0]
	var state: CombatState = pair[1]
	var p := Projectile.new()
	p.id = 9
	p.position = Vector2(50.0, 25.0)
	state.projectiles.append(p)

	view._render(0.5, false)
	assert_eq(view._arena.shot_positions.get(9), Vector2(50.0, 25.0),
		"a projectile's first frame must not interpolate from nothing")
	view.free()
