extends Button
class_name GlossaryButton


## A Button that shows a themed glossary popup on hover, same pattern and
## same reasoning as GlossaryLabel — a plain `Button.new()` needing the
## hover-info-box system's shared styling rather than the engine's default
## grey tooltip. Set `tooltip_text`, `set_script` this.

func _make_custom_tooltip(for_text: String) -> Object:
	return GlossaryTooltip.build(for_text)

## Issue 112: a right-click pins. This is the host that proves the gesture had
## to be right-click -- left-click on "Start Fight" starts the fight, and a
## popout that could only be pinned by doing that would be unreachable on every
## control worth pinning. `_gui_input` sees a right-click without the Button
## emitting `pressed`, so nothing this button does is intercepted.
func _gui_input(event: InputEvent) -> void:
	if PopoutHost.handle_input(self, event, text, tooltip_text):
		accept_event()
