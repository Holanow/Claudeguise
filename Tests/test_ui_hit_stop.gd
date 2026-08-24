extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 515: the picture holds still for a moment on a death. Gated to deaths
## rather than to hits because the simulation runs at 15Hz and a scrum lands
## several hits in one tick, which reads as stutter and not as weight.

const FRAME := 1.0 / 60.0

## `setup`, not `_reset`: the runner calls `setup`. `test_ui_display_options.gd`
## defines a `_reset` nothing ever calls, which is why the toggle-off test below
## leaked into the banner test until this was named right.
func setup() -> void:
	DisplayOptions.reset()

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

## Far enough away that the fight never resolves on its own: once `outcome` is
## set the drain stops and every measurement below would prove nothing.
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

func _fight():
	var state := CombatState.new(11)
	state.units.append(_walker())
	state.units.append(_quarry())
	var view = in_tree(BattleScene.instantiate())
	view._ready()
	view.state = state
	view.event_cursor = 0
	view._rebuild_units()
	view._curr_drawn = view._drawn_snapshot()
	return view

## Through `consume_events`, the path the game takes.
func _feed(view, kind: int, target_id: int = 1) -> void:
	var e := CombatEvent.make(kind, view.state.tick)
	e.target_id = target_id
	e.source_id = 0
	e.amount = 7
	view.state.events.append(e)
	view.consume_events()

func _frames(view, count: int) -> void:
	for i in count:
		view._process(FRAME)

func test_a_death_freezes_the_picture() -> void:
	var view = _fight()
	_feed(view, CG.EventKind.DEATH)
	var tick_at_death: int = view.state.tick

	# Five frames is 0.083s, inside the 0.1s hold, and is more than the 0.067s
	# one tick costs -- so without the freeze this would have stepped.
	_frames(view, 5)
	assert_eq(view.state.tick, tick_at_death,
		"the fight must not advance while the picture is held")

## THE TRAP IN THE ISSUE, and it needs a control rather than arithmetic: a
## banked freeze and a dropped one both end with the same accumulator a moment
## later, and only the tick counts tell them apart.
const _SPAN := 24

func _ticks_per_frame(view, count: int) -> Array[int]:
	var out: Array[int] = []
	for i in count:
		var before: int = view.state.tick
		view._process(FRAME)
		out.append(view.state.tick - before)
	return out

func _sum(a: Array[int]) -> int:
	var n := 0
	for v in a:
		n += v
	return n

## A freeze that accrues real time and releases it repays every frozen frame as
## a lurch, which undoes #501 at the exact moment the player is looking hardest.
## The time is dropped: the frozen run must end up STRICTLY BEHIND the control
## and must never step twice in one frame catching up.
func test_the_freeze_does_not_bank_the_delta() -> void:
	DisplayOptions.set_enabled(&"hit_stop", false)
	var control = _fight()
	_frames(control, 8)
	_feed(control, CG.EventKind.DEATH)
	var without := _sum(_ticks_per_frame(control, _SPAN))

	DisplayOptions.set_enabled(&"hit_stop", true)
	var frozen = _fight()
	_frames(frozen, 8)
	_feed(frozen, CG.EventKind.DEATH)
	var per_frame := _ticks_per_frame(frozen, _SPAN)

	assert_true(_sum(per_frame) < without,
		"a dropped freeze must lose ticks: %d against the control's %d" % [
			_sum(per_frame), without])
	assert_eq(per_frame.max(), 1,
		"no frame may step twice; a catch-up burst is the banked delta showing")

func test_damage_without_a_death_does_not_freeze() -> void:
	var view = _fight()
	_feed(view, CG.EventKind.DAMAGE)
	assert_eq(view._freeze_left, 0.0,
		"a hit is not a death; freezing on every hit is the stutter #515 refuses")

func test_the_toggle_off_means_no_freeze() -> void:
	DisplayOptions.set_enabled(&"hit_stop", false)
	var view = _fight()
	_feed(view, CG.EventKind.DEATH)
	var tick_at_death: int = view.state.tick

	assert_eq(view._freeze_left, 0.0, "hit stop off must not arm a freeze")
	_frames(view, 5)
	assert_true(view.state.tick > tick_at_death,
		"with hit stop off the fight keeps stepping through a death")

func test_several_deaths_in_one_tick_share_one_freeze() -> void:
	var view = _fight()
	_feed(view, CG.EventKind.DEATH)
	var one: float = view._freeze_left
	_feed(view, CG.EventKind.DEATH)
	_feed(view, CG.EventKind.DEATH)
	assert_almost_eq(view._freeze_left, one, 0.0001,
		"three deaths in one tick are one hold, not three stacked into a stall")

## The fight-ending death is the one the player watches hardest, and a banner
## painted over it during the hold is the worst possible moment for it.
func test_the_banner_waits_out_a_freeze_and_then_appears() -> void:
	var view = _fight()
	_feed(view, CG.EventKind.DEATH)
	view.state.outcome = CombatState.Outcome.PLAYER_WIN

	view._process(FRAME)
	assert_false(view._end_banner.visible,
		"the banner must not cover the death the freeze exists to show")
	_frames(view, 8)
	assert_true(view._end_banner.visible,
		"and it must appear once the hold is over, not never")

## A freeze must survive a pause rather than being spent by it: the frames a
## paused view is given are not frames the player watched.
func test_pausing_holds_the_freeze_rather_than_spending_it() -> void:
	var view = _fight()
	_feed(view, CG.EventKind.DEATH)
	var armed: float = view._freeze_left
	view.set_paused(true)
	_frames(view, 20)
	assert_almost_eq(view._freeze_left, armed, 0.0001,
		"a paused view must not burn its freeze down")
