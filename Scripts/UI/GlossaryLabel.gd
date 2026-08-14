extends Label

const GlossaryTooltip := preload("res://Scripts/UI/GlossaryTooltip.gd")

## A Label that shows a themed glossary popup on hover, for the ad hoc
## `Label.new()` chips existing screens already build (InspectPanel's
## attribute chips, its class-tags header line). Same pattern the codebase
## already uses for a plain node needing behaviour it wasn't built with —
## `card.set_script(PartyCardScript)` in PartySelect.gd — rather than a new
## Label subclass at every call site: build a bare Label, `set_script`
## this, set `tooltip_text`.
##
## Set `tooltip_text` (a real Control property, inherited) to the glossary
## sentence; Godot calls `_make_custom_tooltip` with that same text, so
## there is exactly one string to set, not two.

func _make_custom_tooltip(for_text: String) -> Object:
	return GlossaryTooltip.build(for_text)
