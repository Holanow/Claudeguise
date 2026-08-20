extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 343, the playtester's #1 obstacle and the reason they said they would
## not play again: "Every question I formed during a fight was unanswerable
## after it." Measured first with `Tools/EndScreenProbe.gd`, which pushed real
## mouse events at real screen positions and reported that all five toolbar
## buttons, the log and its scrollbar were reached by one full-screen
## `ColorRect` -- the end banner's own backdrop. These assert the structural
## property that made that true, which no assertion in the suite could see.

func _spawn() -> Node2D:
	var view = BattleScene.instantiate()
	view._ready()
	return view

func _resolved(view) -> void:
	var state := CombatState.new(0)
	state.tick = 90
	state.outcome = CombatState.Outcome.PLAYER_WIN
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.hp = 10
	u.hp_max = 10
	u.display_name = "Warrior"
	state.units.append(u)
	view.state = state
	view._show_outcome()

## The whole defect in one assertion: nothing the banner owns may take a mouse
## event except the banner's own buttons.
func test_the_end_banner_does_not_swallow_the_screen_underneath_it() -> void:
	var view = _spawn()
	_resolved(view)
	assert_eq(view._end_banner.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"a full-rect banner on MOUSE_FILTER_STOP is what killed the whole toolbar")
	for child in view._end_banner.get_children():
		assert_false(child is ColorRect,
			"the dim is a sibling now; a full-screen ColorRect inside the banner is the defect")
	view.free()

## Order, not opacity: the dim sits in front of Hud's children so the log, the
## toolbar and the team panel draw over it rather than through it.
func test_both_dims_sit_behind_the_log_and_the_toolbar() -> void:
	var view = _spawn()
	var hud := view.get_node("Hud")
	var log_index := hud.get_children().find(view._combat_log)
	assert_true(log_index >= 0, "the log is not a child of Hud, so this test measures nothing")
	assert_true(hud.get_children().find(view._end_dim) < log_index,
		"the Victory dim draws over the log, which is exactly what issue 343 reports")
	assert_true(hud.get_children().find(view._pause_dim) < log_index,
		"pausing to read the log must not dim the log")
	view.free()

func test_the_dim_follows_the_banner_on_and_off() -> void:
	var view = _spawn()
	assert_false(view._end_dim.visible, "the dim must be silent until the fight resolves")
	_resolved(view)
	assert_true(view._end_dim.visible)
	view.free()

## The log is anchored full-rect and draws only the box in the corner. Left on
## the Control default it is a screen-sized click target.
func test_the_log_is_not_a_screen_sized_click_target() -> void:
	var view = _spawn()
	assert_eq(view._combat_log.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_ne(view._combat_log._label.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the label itself must still take the wheel, or the log cannot be scrolled at all")
	view.free()

## The end card offered "Inspect party" for the screen the toolbar calls
## "Plans", and the playtester never connected the two.
func test_the_end_card_calls_the_plans_screen_what_the_toolbar_calls_it() -> void:
	var view = _spawn()
	_resolved(view)
	var labels: Array[String] = []
	for n in _walk(view._end_banner):
		if n is Button:
			labels.append(n.text)
	assert_true(labels.has("Plans"), "the end card's buttons are %s" % [labels])
	assert_false(labels.has("Inspect party"),
		"two names for one screen is what stopped the playtester finding it")
	view.free()

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
