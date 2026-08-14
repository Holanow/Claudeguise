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
##
## PLAYTEST-NOTES-2 item 13: "hover is missing on Inspect classes — the
## most important place for it to be." Found by driving the real screen
## through its own "Inspect classes" button (a throwaway probe, not the
## direct InspectPanel.open() the unit tests use, which never touches
## input at all) and reading every ancestor's own mouse_filter: this
## node's was 2 (MOUSE_FILTER_IGNORE), Label's own engine default. A plain
## Control defaults to STOP, which is why PartyCard's tooltip worked and
## every ad hoc Label built for one never could -- the eighth
## built-and-unreachable on this project, and it was sitting in the one
## line every other hoverable node gets for free by being a different
## base class.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _make_custom_tooltip(for_text: String) -> Object:
	return GlossaryTooltip.build(for_text)
