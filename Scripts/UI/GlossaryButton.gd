extends Button

const GlossaryTooltip := preload("res://Scripts/UI/GlossaryTooltip.gd")

## A Button that shows a themed glossary popup on hover, same pattern and
## same reasoning as GlossaryLabel — a plain `Button.new()` needing the
## hover-info-box system's shared styling rather than the engine's default
## grey tooltip. Set `tooltip_text`, `set_script` this.

func _make_custom_tooltip(for_text: String) -> Object:
	return GlossaryTooltip.build(for_text)
