extends RefCounted
class_name AppTheme

## One Theme, built from Palette so the values keep a single source. A hand
## written .tres would duplicate every colour and drift from Palette, which is
## the split issue 180 was filed for.

static var _shared: Theme = null

static func shared() -> Theme:
	if _shared != null:
		return _shared
	var t := Theme.new()
	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_font_size("font_size", "Label", Palette.FONT_SIZE_BODY)
	t.set_constant("separation", "HBoxContainer", int(Palette.SPACE_S))
	t.set_constant("separation", "VBoxContainer", int(Palette.SPACE_S))
	_shared = t
	return _shared
