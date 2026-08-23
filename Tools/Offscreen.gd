extends RefCounted
class_name Offscreen

## Move a screenshot tool's window off the desktop so a capture run does not
## take over the machine somebody is using.
##
## Call `Offscreen.hide_window(self)` first thing in `_ready()`, before the
## first `await RenderingServer.frame_post_draw`.
static func hide_window(node: Node) -> bool:
	if not require_renderer(node):
		return false
	var w := node.get_window()
	if w == null:
		return true
	w.set_flag(Window.FLAG_NO_FOCUS, true)
	w.position = Vector2i(-4000, -4000)
	return true

## Quits the run at once when there is no renderer, rather than letting the tool
## reach an `await` that can never resume.
##
## `--headless` and a minimized window both stop the renderer drawing, so
## `RenderingServer.frame_post_draw` never fires. The warning this replaces was
## a paragraph in this header and three sessions walked past it in one night;
## one process burned 650 seconds of CPU in a loop that could not terminate
## (#478). `quit()` still takes effect from inside a coroutine that is about to
## suspend forever, because the main loop keeps iterating without it.
static func require_renderer(node: Node) -> bool:
	if DisplayServer.get_name() != "headless":
		return true
	printerr("This tool draws frames, and --headless has no renderer, so")
	printerr("  RenderingServer.frame_post_draw would never fire and the run would")
	printerr("  hang rather than fail. Launch it with:")
	printerr("    powershell -ExecutionPolicy Bypass -File Tools\run.ps1 <ToolName>")
	if node.get_tree() != null:
		node.get_tree().quit(4)
	return false
