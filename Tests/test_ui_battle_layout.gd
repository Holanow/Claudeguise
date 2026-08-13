extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const BattleView := preload("res://Scripts/UI/BattleView.gd")
const CombatLogView := preload("res://Scripts/UI/CombatLogView.gd")

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

## Issue 26, item 2: the arena's bottom edge must clear the log strip, not
## just the viewport. Tools/preview/fight_05.png had three of seven units
## drawn behind the log's own text before this — the world-space
## _MARGIN_BOTTOM cleared a unit's own bars/label but not the fixed
## screen-pixel log panel on top of it.
func test_arena_bottom_edge_clears_the_combat_log_strip() -> void:
	var size := Vector2(1280.0, 720.0)
	var layout := BattleView.compute_layout(size)
	var arena_bottom: float = layout.position.y + CG.ARENA_HALF_HEIGHT * layout.scale.y
	assert_true(arena_bottom <= size.y - CombatLogView.LOG_HEIGHT,
		"arena bottom edge (%f) overlaps the log strip starting at %f" % [
			arena_bottom, size.y - CombatLogView.LOG_HEIGHT])

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
