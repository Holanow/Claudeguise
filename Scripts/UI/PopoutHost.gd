extends RefCounted
class_name PopoutHost


## Issue 112: the gesture that pins a popout, defined once.
##
## OWNER: wren.
##
## Every hoverable control on this project keeps its glossary sentence in
## `tooltip_text` and returns `GlossaryTooltip.build(...)` from its own
## `_make_custom_tooltip`. That hover is untouched: it is discoverable, it is
## what the player already knows, and a popout that needed a different gesture
## to appear would be a second system beside it rather than the same one.
##
## **Right-click pins.** One gesture, on every host, and it was chosen because
## it is the only one that cannot collide with what the control already does.
## Two of the three hosts are things you click for another reason -- a
## `GlossaryButton` starts the fight, a `PartyCard` picks a pawn -- so
## left-click was never available, and a modifier is a gesture nobody
## discovers. `_gui_input` receives a right-click on a Button without the
## Button emitting `pressed`, so nothing is intercepted.
##
## Discoverability is `GlossaryTooltip`'s job: every hover box ends with the
## sentence naming the gesture, so the only place a player can learn it is the
## place they are already looking. No emoji and no icon, per the copy rules.

const PIN_HINT := "Right-click to pin this."

## Call from a host's `_gui_input`. Returns true when the event was a pin, so
## the host can `accept_event()` and nothing else reads it.
##
## `title` is the host's own visible text where it has one -- an attribute chip
## reads "STR 12", an action chip reads "Strike" -- because that is the word the
## player right-clicked and the only thing that tells two pinned popouts apart.
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
