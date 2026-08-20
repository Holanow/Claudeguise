extends RefCounted
class_name PopoutHost


## Issue 112: the gesture that pins a popout, defined once.

const PIN_HINT := "Right-click to pin this."

## Call from a host's `_gui_input`. Returns true when the event was a pin, so
## the host can `accept_event()` and nothing else reads it.
static func handle_input(host: Control, event: InputEvent, title: String, body: String) -> bool:
	if not (event is InputEventMouseButton):
		return false
	if event.button_index != MOUSE_BUTTON_RIGHT or not event.pressed:
		return false
	if body.strip_edges() == "":
		return false
	return pin_from(host, title, body) != null

## Pins at the host's bottom-left corner in the layer's own coordinates, so the
## popout appears attached to the thing it describes rather than wherever the
## pointer happened to be.
static func pin_from(host: Control, title: String, body: String) -> Control:
	var layer := PopoutLayer.of(host)
	if layer == null:
		return null
	var at: Vector2 = host.global_position - layer.global_position + Vector2(0.0, host.size.y)
	# Issue 245: the host goes with it, so a popout carrying a live number can be
	# re-read from the control it describes instead of freezing at the tick it was
	# pinned on.
	return layer.pin(title if title != "" else "Detail", body, at, host)
