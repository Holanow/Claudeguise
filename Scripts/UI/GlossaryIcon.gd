extends Control


## Issue 591: a picture that explains itself on hover, for the icons and
## portraits screens draw rather than write. Same pattern and same reasoning as
## `GlossaryLabel` and `GlossaryButton` -- set `tooltip_text`, `set_script`
## this -- except that its base is `Control`, so a `TextureRect` or a
## `ColorRect` can take it too.

## What a pinned popout is titled. Empty pins nothing readable, so a host with
## no title is treated as a host with nothing to say.
var pin_title: String = ""

## A bare `Control` defaults to MOUSE_FILTER_STOP already; a `TextureRect` does
## not, and neither does anything else that draws a picture.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _make_custom_tooltip(for_text: String) -> Object:
	return GlossaryTooltip.build(for_text, pin_title)

## Issue 112's gesture, unchanged: right-click pins.
func _gui_input(event: InputEvent) -> void:
	if PopoutHost.handle_input(self, event, pin_title, tooltip_text):
		accept_event()
