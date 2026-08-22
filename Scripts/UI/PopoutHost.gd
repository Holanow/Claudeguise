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

## Issue 449: pins at a point in screen coordinates instead. For a host that
## covers the whole screen, whose corner therefore says nothing about which of
## the many things on it was hovered.
static func pin_at(host: Control, title: String, body: String, screen_point: Vector2) -> Control:
	var layer := PopoutLayer.of(host)
	if layer == null:
		return null
	# No source, so nothing re-reads it. `Popout.refresh` re-reads the host's
	# `tooltip_text`, and a whole-screen host has no single one -- it would blank
	# every popout pinned off the arena on the next tick.
	return layer.pin(title if title != "" else "Detail", body,
		screen_point - layer.get_global_transform_with_canvas().origin)
