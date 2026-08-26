extends RefCounted
class_name StatusIcons


## One badge per `CG.Status`, for PLAYTEST-NOTES-2 item 2:

## The rim colour. The tab below inherits it rather than inventing a third
## colour, so a red tab can never appear on a helpful badge.
static func rim_color(status: CG.Status) -> Color:
	return Palette.HP_LOW if CG.is_harmful(status) else Palette.HP_FULL

## The file this badge is drawn from: `Assets/UI/status/bleed.png`. Authored on
## the `StatusDef` rather than derived from the enum name, so the icon sits
## beside everything else the status is; every one of the thirteen is still the
## lower-cased enum name, and the transcription test holds them to it.
static func art_name(status: CG.Status) -> StringName:
	return StatusLibrary.of(status).icon_name

static func has_glyph(status: CG.Status) -> bool:
	return UIArt.has_art(art_name(status))

## One badge filling `rect`. On screen today it is 17.4px: `UnitView`'s
## `STATUS_BADGE_SIZE` of 14 through `DISPLAY_SCALE` and the arena's own scale.
static func draw_status(canvas: CanvasItem, status: CG.Status, rect: Rect2, stacks: int = 1) -> void:
	var tex := UIArt.texture_for(art_name(status))
	if tex != null:
		UIArt.draw_fit(canvas, tex, rect)
	else:
		canvas.draw_rect(rect, Color.BLACK)

	# OUTSIDE BOTH BRANCHES, AND THAT IS THE WHOLE POINT. The count is
	# information; the badge behind it is decoration. A picture may replace
	# decoration and it may not replace information -- this project has learned
	# that three times, twice by breaking it.
	if shows_stack_count(stacks):
		draw_stack_count(canvas, status, rect, stacks)

## Whether a count is drawn at all. One is the ordinary case and gets no
## decoration -- a badge that always carries "1" is noise on eleven statuses
## that cannot stack.
static func shows_stack_count(stacks: int) -> bool:
	return stacks >= 2

## What the tab reads. Capped at two digits because the tab is about ten pixels
## wide on screen and a third digit would be a smudge rather than a number.
static func stack_text(stacks: int) -> String:
	return "99+" if stacks > 99 else str(stacks)

## Where the count tab sits: **on the plate's FLAT edge, never on its point, and
## never wider than the badge.** Both halves were found by rendering it.
static func stack_count_rect(status: CG.Status, rect: Rect2, stacks: int) -> Rect2:
	var unit := minf(rect.size.x, rect.size.y)
	var height := unit * 0.58
	# Width from the text that will actually be drawn, not from a per-digit
	# multiplier: the multiplier was written for two characters and "99+" is
	# three, so the plus sign hung outside its own pill.
	var width := minf(rect.size.x, height * (0.62 + 0.46 * float(stack_text(stacks).length())))
	var y := rect.position.y - height * 0.5
	if not CG.is_harmful(status):
		y = rect.position.y + rect.size.y - height * 0.5
	return Rect2(Vector2(rect.position.x + rect.size.x - width, y), Vector2(width, height))

## The tab itself. Split from `draw_status` so the geometry above can be tested
## without a live canvas: `draw_*` outside `_draw()` logs a wall of errors and
## asserts nothing.
static func draw_stack_count(canvas: CanvasItem, status: CG.Status, rect: Rect2, stacks: int) -> void:
	var tab := stack_count_rect(status, rect, stacks)
	var text := stack_text(stacks)
	var radius := tab.size.y * 0.5
	canvas.draw_rect(Rect2(tab.position + Vector2(radius, 0.0), Vector2(maxf(tab.size.x - radius * 2.0, 0.0), tab.size.y)), rim_color(status))
	canvas.draw_circle(tab.position + Vector2(radius, radius), radius, rim_color(status))
	canvas.draw_circle(tab.position + Vector2(tab.size.x - radius, radius), radius, rim_color(status))
	var font := ThemeDB.fallback_font
	var size := maxi(7, int(tab.size.y * 0.92))
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := tab.position + Vector2(
		(tab.size.x - text_width) * 0.5,
		(tab.size.y + float(font.get_ascent(size)) - float(font.get_descent(size))) * 0.5)
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.HP_BACK)

## Where a row of badges goes, left to right from `top_left`. Returned rather
## than drawn so the caller decides how many fit -- that is a layout call.
static func layout_row(top_left: Vector2, count: int, size: float, gap: float = Palette.SPACE_XS) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in count:
		out.append(Rect2(top_left + Vector2(float(i) * (size + gap), 0.0), Vector2(size, size)))
	return out

## Total width a row of `count` badges occupies, so a caller can centre it over
## a unit without rediscovering the arithmetic.
static func row_width(count: int, size: float, gap: float = Palette.SPACE_XS) -> float:
	if count <= 0:
		return 0.0
	return float(count) * size + float(count - 1) * gap
