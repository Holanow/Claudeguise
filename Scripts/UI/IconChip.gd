extends Control
class_name IconChip


## One small icon with a word beside it, hoverable and pinnable.

enum Kind { STATUS, ACTION }

const ICON_SIZE := 18.0
const TEXT_GAP := 3.0

var kind: Kind = Kind.STATUS
var status: CG.Status = CG.Status.SHIELD
var action_id: StringName = &""
var damage_type: CG.DamageType = CG.DamageType.PHYSICAL

## Word beside the icon. Empty draws the icon alone at ICON_SIZE square.
var text: String = ""
var text_color: Color = Palette.INK_DIM

## 0.0 to 1.0 of the icon darkened from the top down, the share of a cooldown
## still to run. Negative means "no sweep", which is every status chip and an
## action chip that is ready.
var sweep: float = -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(measured_width(), ICON_SIZE)

func measured_width() -> float:
	if text == "":
		return ICON_SIZE
	var font := ThemeDB.fallback_font
	return ICON_SIZE + TEXT_GAP + font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL).x

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(ICON_SIZE, ICON_SIZE))
	if kind == Kind.STATUS:
		StatusIcons.draw_status(self, status, rect)
	else:
		ActionIcons.draw_action(self, action_id, damage_type, rect)
	if sweep > 0.0:
		# Over the icon, not instead of it: the player still has to be able to
		# tell which action is waiting, which is the whole reason a cooldown
		# indicator names an action rather than lighting a lamp.
		var shade := Palette.PAPER_LEAF
		shade.a = 0.66
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * minf(sweep, 1.0))), shade)
	if text != "":
		var font := ThemeDB.fallback_font
		var baseline := ICON_SIZE * 0.5 + float(Palette.FONT_SIZE_SMALL) * 0.35
		draw_string(font, Vector2(ICON_SIZE + TEXT_GAP, baseline), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, text_color)

## Issue 245: the hover box gets the same title the pinned copy gets, so the two
## surfaces name the thing once each rather than the body carrying a name the
## popout then repeats above it.
func _make_custom_tooltip(for_text: String) -> Object:
	return GlossaryTooltip.build(for_text, pin_title)

## Issue 112's gesture, unchanged. The title is what the chip says where it says
## anything and the icon's own name otherwise, because a pinned popout with no
## title cannot be told from the one pinned beside it.
var pin_title: String = ""

func _gui_input(event: InputEvent) -> void:
	if PopoutHost.handle_input(self, event, pin_title if pin_title != "" else text, tooltip_text):
		accept_event()
