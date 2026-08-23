extends "res://Tests/TestCase.gd"


## A tool that waits for a drawn frame must refuse a run that draws none.

## Issue 478: `--headless` stops the renderer, so `frame_post_draw` never fires
## and the tool hangs instead of failing. `Offscreen.require_renderer` quits on
## line one; `Offscreen.hide_window` calls it, so either satisfies this.
const TOOLS_DIR := "res://Tools"

const WAITS_FOR_A_FRAME := "RenderingServer.frame_post_draw"

const REFUSALS := ["Offscreen.hide_window(", "Offscreen.require_renderer("]


func test_every_tool_that_waits_for_a_frame_refuses_a_headless_run() -> void:
	var offenders: Array[String] = []
	for path in _tool_scripts():
		var source := FileAccess.get_file_as_string(path)
		if not source.contains(WAITS_FOR_A_FRAME):
			continue
		if not _refuses(source):
			offenders.append(path)
	assert_eq(offenders, [] as Array[String],
		"these await a frame --headless will never draw, and nothing stops them:\n  %s"
			% "\n  ".join(offenders))


func test_the_guard_fires_on_a_tool_that_forgot() -> void:
	# The negative half. `Offscreen.gd` itself names `frame_post_draw` in prose
	# and must not count as a tool that waits for one, which is why the check
	# reads the call and not the word.
	assert_false(_refuses("func _ready():\n\tawait RenderingServer.frame_post_draw\n"),
		"a tool with no refusal must be flagged")
	assert_true(_refuses("func _ready():\n\tOffscreen.hide_window(self)\n"),
		"hide_window refuses on the tool's behalf")
	assert_true(_refuses("func _ready():\n\tif not Offscreen.require_renderer(self):\n\t\treturn\n"),
		"the explicit refusal counts")
	assert_false(_refuses("## Do not reach for Offscreen.hide_window here\n".replace("(", " ")),
		"prose about the call is not the call")


## `hide_window` must actually be the refusal, or every tool that calls it is
## relying on something that does not happen.
func test_hide_window_goes_through_require_renderer() -> void:
	var source := FileAccess.get_file_as_string("res://Tools/Offscreen.gd")
	assert_true(source.contains("require_renderer(node)"),
		"hide_window must delegate to require_renderer")
	assert_true(source.contains("DisplayServer.get_name() != \"headless\""),
		"the refusal must test the display driver")


func _refuses(source: String) -> bool:
	for call in REFUSALS:
		if source.contains(call):
			return true
	return false


func _tool_scripts() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TOOLS_DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".gd") and name != "Offscreen.gd":
			out.append("%s/%s" % [TOOLS_DIR, name])
	return out
