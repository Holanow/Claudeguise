extends RefCounted
class_name GlossaryTooltip


const PIN_HINT := PopoutHost.PIN_HINT

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

## Issue 112: every hover box ends by naming the gesture that pins it. The hint
## is added here rather than written into each `tooltip_text`, so it cannot be
## forgotten on a new hoverable control and cannot go stale in fifteen places if
## the gesture changes. It is also why it is not in `tooltip_text` itself: tests
## and callers read that string as the glossary sentence, and it is.
##
## Discoverability was a build note on the issue. A gesture that appears in a
## manual nobody opens is the same as no gesture; this is the one place a player
## is already reading when the gesture is useful.
## Issue 245: `title` is optional and empty is exactly the old behaviour.
##
## It exists because a hover box and its pinned twin carry the same string and
## show it differently: `Popout` draws a title row of its own, a hover box has
## nowhere to put one. The status popup needs the status named -- a player
## hovering an unfamiliar badge wants the name most of all -- and putting the
## name into the body instead made the **pinned** copy say "Taunting" twice,
## once as its title and once as its first line. Caught on the screen, not in a
## test; the string was correct in both places and only the picture showed it.
##
## So the name is passed as a title to both, and each renders it where it has
## room. `Popout` already had this shape; this is the tooltip catching up.
static func build(text: String, title: String = "") -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style())

	var label := Label.new()
	var head := "" if title == "" else "%s\n\n" % title
	label.text = "%s%s\n\n%s" % [head, text, PIN_HINT]
	label.custom_minimum_size = Vector2(_MAX_WIDTH, 0.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", Palette.TEXT)
	panel.add_child(label)
	return panel

## Same shape as PartySelect's own `_seed_box_style` — a bordered box in
## existing Palette tokens, no new colour or spacing literal. Through
## `UIArt.panel_style` since issue 268, so `Assets/UI/panel.png` reaches it;
## with no file present it is the same flat box, to the pixel.
static func _style() -> StyleBox:
	return UIArt.panel_style(&"", Palette.ARENA_FLOOR, Palette.ARENA_EDGE, 1, Palette.SPACE_S)
