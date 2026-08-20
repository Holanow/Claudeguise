extends Label

const GlossaryTooltip := preload("res://Scripts/UI/GlossaryTooltip.gd")
const PopoutHost := preload("res://Scripts/UI/PopoutHost.gd")

## A Label that shows a glossary popup on hover, for the ad hoc `Label.new()`
## chips screens already build. Build a bare Label, `set_script` this, set
## `tooltip_text`; Godot hands that same text to `_make_custom_tooltip`.

## Label's engine default is MOUSE_FILTER_IGNORE where a plain Control defaults
## to STOP, so without this an ad hoc Label can never receive hover at all.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _make_custom_tooltip(for_text: String) -> Object:
	return GlossaryTooltip.build(for_text)

## Issue 112: right-click pins a popout titled with this chip's own text.
func _gui_input(event: InputEvent) -> void:
	if PopoutHost.handle_input(self, event, text, tooltip_text):
		accept_event()
