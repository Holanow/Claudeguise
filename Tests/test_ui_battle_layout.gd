extends "res://Tests/TestCase.gd"


## Issue 18: the arena must not run off any edge at 844x390 (landscape phone,
## the size that "has to be good") and 390x844 (portrait, has to "not be
## broken"). BattleView.compute_layout is pure, so these check the actual
## fit math against get_viewport_rect() values measured on real
## --resolution launches (see the const comments in BattleView.gd for how
## those were obtained) rather than eyeballing a screenshot.

func _arena_width(layout: Dictionary) -> float:
	return CG.ARENA_HALF_WIDTH * 2.0 * layout.scale.x

func _arena_height(layout: Dictionary) -> float:
	return CG.ARENA_HALF_HEIGHT * 2.0 * layout.scale.y

func test_arena_never_exceeds_the_visible_width_at_landscape_phone_size() -> void:
	# Measured viewport for a real 844x390 launch.
	var layout := BattleView.compute_layout(Vector2(1558.0, 720.0))
	assert_true(_arena_width(layout) <= 1558.0, "arena must not run off the side edges")
	assert_true(_arena_height(layout) <= 720.0, "arena must not run off the top/bottom edges")

func test_arena_is_the_largest_thing_on_screen_at_landscape_phone_size() -> void:
	var size := Vector2(1558.0, 720.0)
	var layout := BattleView.compute_layout(size)
	# "Largest thing on screen": at minimum, more than half the height, since
	# nothing else (HUD strip, log strip) claims anywhere near that much.
	assert_true(_arena_height(layout) / size.y > 0.5)

func test_arena_never_exceeds_the_visible_area_at_portrait_phone_size() -> void:
	# Measured viewport for a real 390x844 launch. window/stretch/mode
	# canvas_items + expand pins width to the design width and inflates
	# height here (see BattleView.gd's own comment on this exact case).
	var layout := BattleView.compute_layout(Vector2(1280.0, 2770.0))
	assert_true(_arena_width(layout) <= 1280.0,
		"must stay fully visible — the alternative (crop to hit 50% height) hid the entire party, a worse failure")
	assert_true(_arena_height(layout) <= 2770.0)

## Issue 825 REPLACES issue 29's version of this test, which asserted the
## opposite: the arena's right edge used to have to clear the log strip. The log
## is an overlay on the fight now, so the arena is fitted to the whole window and
## the property worth pinning is that nothing is subtracted from it.
func test_the_arena_is_fitted_to_the_whole_window_not_the_window_minus_the_log() -> void:
	var size := Vector2(1280.0, 720.0)
	var full := BattleView.compute_layout(size)
	var minus_log := BattleView.compute_layout(Vector2(size.x - CombatLogView.LOG_WIDTH, size.y))
	assert_true(full.scale.x > minus_log.scale.x,
		"the arena is still being fitted to a window narrowed by the log: %f against %f" % [
			full.scale.x, minus_log.scale.x])
	var arena_right: float = full.position.x + CG.ARENA_HALF_WIDTH * full.scale.x
	assert_true(arena_right <= size.x, "the arena must still not run off the right edge")

## Issue 29's own criterion 1: the arena must be measurably larger at
## 1280x720 than the bottom-docked version was. Pinned against the actual
## regression this replaced rather than an arbitrary number: the old
## bottom-log layout left the arena at roughly a quarter of the screen
## (rook's own measurement in the issue).
func test_arena_is_measurably_larger_than_the_bottom_docked_log_left_it() -> void:
	var size := Vector2(1280.0, 720.0)
	var layout := BattleView.compute_layout(size)
	var fraction := _arena_height(layout) / size.y
	assert_true(fraction > 0.4, "arena should be well above the old ~quarter-screen fraction, got %f" % fraction)

func test_portrait_height_fraction_is_a_known_geometric_limit_not_a_regression() -> void:
	# Documents the actual number rather than letting a future change to the
	# margin constants silently drift it without anyone noticing: criterion 2
	# asks for 50%, and a fully-visible 16:9 arena cannot reach that under
	# this stretch mode's portrait behaviour (see BattleView.gd). This pins
	# what "not broken" currently measures as, so a regression below it is
	# caught even though the 50% target itself is not reachable without
	# cropping.
	var size := Vector2(1280.0, 2770.0)
	var layout := BattleView.compute_layout(size)
	var fraction := _arena_height(layout) / size.y
	assert_true(fraction > 0.2, "should not have regressed below the measured ~24%%, got %f" % fraction)

## Issue 825 REPLACES issue 396's version of this test, which pinned a toolbar
## that no longer exists. What survives is the property under it: an overlay
## opened over the fight starts inside the window rather than off the top of it.
func test_an_overlay_over_the_fight_opens_inside_the_window() -> void:
	var view = in_tree(preload("res://Scenes/Battle.tscn").instantiate())
	for overlay in [view._display_options, view._inspect_panel]:
		assert_true(overlay.position.y >= 0.0 and overlay.position.x >= 0.0,
			"an overlay opens at %s, off the window" % [overlay.position])

## The five toolbar buttons are gone and nothing on the fight screen replaces
## them, so a control on the arena outside placement is a regression.
func test_no_button_stands_on_the_running_fight() -> void:
	var view = in_tree(preload("res://Scenes/Battle.tscn").instantiate())
	assert_false(view._pause_button.visible,
		"the setup row must be hidden until begin_setup shows it")
	for node in view.get_node("Hud").get_children():
		assert_false(node is HBoxContainer and node.name != "SetupControls",
			"an unexpected control row '%s' is on the battle screen" % node.name)
