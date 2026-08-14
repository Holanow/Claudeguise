extends RefCounted

const Palette := preload("res://Scripts/Core/Palette.gd")

## The one themed popup every hoverable node in the hover-info-box system
## returns from its own `_make_custom_tooltip`. Godot's own tooltip
## machinery (positioning, the show delay, dismiss-on-move) does the rest —
## see TEAM_LOG.md, wren's block, for why that's the whole mechanism rather
## than a hand-rolled hover manager.
##
## A static builder, not a scene: every caller needs a fresh instance (Godot
## frees the returned Control itself once the tooltip closes), and the
## content is one wrapped Label, too small to be worth a .tscn file for.

const _MAX_WIDTH := 260.0

static func build(text: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style())

	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(_MAX_WIDTH, 0.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", Palette.TEXT)
	panel.add_child(label)
	return panel

## Same shape as PartySelect's own `_seed_box_style` — a bordered box in
## existing Palette tokens, no new colour or spacing literal.
static func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.ARENA_FLOOR
	style.border_color = Palette.ARENA_EDGE
	style.set_border_width_all(1)
	style.set_content_margin_all(Palette.SPACE_S)
	return style
