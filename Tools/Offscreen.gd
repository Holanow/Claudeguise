extends RefCounted
class_name Offscreen

## Move a screenshot tool's window off the desktop so a capture run does not
## take over the machine somebody is using.
##
## Call `Offscreen.hide_window(self)` first thing in `_ready()`, before the
## first `await RenderingServer.frame_post_draw`.
##
## Do NOT reach for `--headless` or a minimized window instead. Both stop the
## renderer drawing frames, `frame_post_draw` never fires, and the tool hangs
## rather than failing: measured, 60s timeout with no output.
static func hide_window(node: Node) -> void:
	var w := node.get_window()
	if w == null:
		return
	w.set_flag(Window.FLAG_NO_FOCUS, true)
	w.position = Vector2i(-4000, -4000)
