extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const UIArt := preload("res://Scripts/Art/UIArt.gd")

## One badge per `CG.Status`, for PLAYTEST-NOTES-2 item 2:
##
##   "There needs to be a clearer visual representation of who is afflicted
##    with what statuses."
##
## Statuses are legible today only from the combat log, which scrolls, in a
## fight the same notes call too fast to read. A badge above the unit is where
## the information belongs.
##
## MANAGER-OWNED (`Scripts/Art/**`). Nothing here draws itself into a fight:
## placement is `Scripts/UI/UnitView.gd`, wren's. See TEAM_LOG.md, sable's
## block, for the call signature.
##
## ---------------------------------------------------------------------------
## THE RULE, WHICH IS A RULE AND NOT PER-ICON TASTE
##
## The note asks that harmful and beneficial be obvious *without* reading the
## glyph. Two redundant channels carry that, and neither is the glyph:
##
##   1. PLATE DIRECTION. A beneficial status sits on a plate that POINTS UP,
##      flat along the bottom. A harmful one sits on a plate that POINTS DOWN,
##      flat along the top. At 12px this is the whole read -- an upward wedge
##      and a downward wedge are still different shapes when nothing inside
##      them survives.
##   2. RIM COLOUR. Cool green rim for beneficial, hot red rim for harmful.
##
## Both, not either. Red-against-green is precisely the pair a colourblind
## player cannot separate, so it is never the only channel; direction is a
## shape cue and works when the colour does not. That redundancy is the
## standing accessibility guidance for status effects and it is cheap here.
##
## `CG.is_harmful()` is the single source of truth for which side a status is
## on. There is deliberately no second list in this file to disagree with it --
## a new status classified there gets the right plate here for free.
##
## The glyph itself is drawn in `Palette.TEXT` on both sides. It answers "which
## status", never "is this good", so it does not compete with the two channels
## that do.

## An upward wedge with a flat bottom -- beneficial. Wider than tall at the
## shoulders so the point reads as a point and not as a corner.
const PLATE_GOOD := [[0.0, -1.0], [0.9, -0.35], [0.9, 1.0], [-0.9, 1.0], [-0.9, -0.35]]

## The same shape mirrored in Y -- harmful. Mirrored rather than redesigned so
## the pair reads as one system, and so the glyph inside sits in the same amount
## of room on both.
const PLATE_BAD := [[0.0, 1.0], [0.9, 0.35], [0.9, -1.0], [-0.9, -1.0], [-0.9, 0.35]]

## Glyphs, in `UIArt.draw_glyph`'s -1..1 part format. Each is kept inside about
## 0.8 of the box so it never touches the plate's own rim.
##
## Chosen for shape family first, meaning first: slash, flame, three dots,
## asterisk, crosshair, weight, turning-arrow | shield, wall, shield-and-arc,
## chevrons, hourglass, horn. No two share an outline, which is what has to hold
## at 12px -- the same finding as the unit roster, where interior detail vanished
## and silhouette did not.
##
## **"No two share an outline" was an assertion for months and it was false.**
## `Tools/BadgeLegibility.tscn` measures how many pixels two badges actually
## disagree on. It found bleed and burn at 2.1% -- the same badge -- and later
## found taunted and burn at 9.3% after an enum rename moved taunted from one
## category to the other. Re-run it after touching anything here.
const GLYPHS := {
	# --- beneficial ---------------------------------------------------------
	# Heater shield. The plainest "protected" read there is.
	CG.Status.SHIELD: [
		{"poly": [[-0.5, -0.55], [0.5, -0.55], [0.5, 0.05], [0.0, 0.65], [-0.5, 0.05]]},
	],
	# A crenellated wall. Damage reduction rather than absorption, and a wall is
	# a different outline from a shield where a thicker shield would not be.
	#
	# Was two stacked bars in the first pass and rendered as an equals sign --
	# caught on the sheet, not reasoned about. The battlements are what make it
	# a wall: a plain rectangle is a rectangle.
	CG.Status.BLOCK: [
		{"poly": [
			[-0.72, -0.52], [-0.44, -0.52], [-0.44, -0.28], [-0.16, -0.28],
			[-0.16, -0.52], [0.16, -0.52], [0.16, -0.28], [0.44, -0.28],
			[0.44, -0.52], [0.72, -0.52], [0.72, 0.5], [-0.72, 0.5],
		]},
	],
	# A bar with an arc bulging off one side: this one is directional, it stops
	# what crosses the front only. The arc is the whole difference from SHIELD.
	CG.Status.SHIELDING: [
		{"poly": [[-0.5, -0.7], [-0.18, -0.7], [-0.18, 0.7], [-0.5, 0.7]]},
		{"arc": [-0.35, 0.0, 0.85, -PI / 3.0, PI / 3.0], "w": 0.2},
	],
	# An hourglass. Issue 61's sustained channel: something the pawn is holding
	# open while a pool drains underneath it.
	#
	# A bowtie is not an outline anything else here has, which is the test this
	# set is held to at 12px. Rejected: radiating arcs around a centre, which is
	# the obvious "aura" reading and is also TAUNTING's horn-and-sound-arcs at
	# small sizes.
	#
	# The hourglass says "running out" rather than "for a fixed time", and for
	# this status the thing running out is resource, not a duration -- a channel
	# ends when the pawn cannot pay for it, and has no clock at all.
	#
	# **swift wrote this, in sable's file.** `test_art.gd` and
	# `test_ui_unit_view.gd` both refuse a CG.Status with no glyph, which is the
	# guard working as intended -- a new status cannot ship invisible. It is one
	# entry and it is meant to be replaced by whoever owns the art.
	CG.Status.SUSTAINING: [
		{"poly": [
			[-0.6, -0.78], [0.6, -0.78], [0.1, 0.0], [0.6, 0.78], [-0.6, 0.78], [-0.1, 0.0],
		]},
	],
	# Double chevron. Faster.
	CG.Status.HASTE: [
		{"poly": [[-0.7, -0.6], [-0.2, 0.0], [-0.7, 0.6], [-0.95, 0.6], [-0.45, 0.0], [-0.95, -0.6]]},
		{"poly": [[0.0, -0.6], [0.5, 0.0], [0.0, 0.6], [-0.25, 0.6], [0.25, 0.0], [-0.25, -0.6]]},
	],
	# A horn with two sound arcs. Forcing attention, not receiving it.
	CG.Status.TAUNTING: [
		{"poly": [[-0.75, -0.42], [-0.12, -0.75], [-0.12, 0.75], [-0.75, 0.42]]},
		{"arc": [-0.12, 0.0, 0.42, -PI / 2.4, PI / 2.4], "w": 0.16},
		{"arc": [-0.12, 0.0, 0.78, -PI / 2.4, PI / 2.4], "w": 0.16},
	],

	# --- harmful ------------------------------------------------------------
	# A pull: an arc turning back on itself with a head on the end. You are not
	# choosing your target any more.
	#
	# **This was three rising spikes, and it was fine until the enum moved.**
	# ENRAGE was renamed TAUNTED in place -- correct, it duplicated TAUNTING --
	# and that quietly moved the badge from the HELPFUL category to the HARMFUL
	# one. Three spikes among green badges was distinct. Beside a red flame it
	# was not: measured at the shipped size it became the closest pair in the
	# whole system at 9.3%, taking the place bleed/burn had just vacated.
	#
	# **Nobody could have seen that from the rename.** The diff was one enum
	# value and a comment; the art consequence was in a file it did not touch,
	# in a comparison that did not exist before. It surfaced because the
	# measurement got re-run, which is the argument for the measurement being a
	# committed tool rather than a thing I did once.
	CG.Status.TAUNTED: [
		{"arc": [0.0, 0.12, 0.60, PI * 0.78, PI * 1.92], "w": 0.26},
		{"poly": [[0.20, -0.86], [0.86, -0.62], [0.36, -0.16]]},
	],
	# A GASH, not a droplet, and the reason is a measurement rather than taste.
	#
	# This was a droplet. BURN is a flame, and a flame is a droplet with a notch
	# taken out of it. Measured at the shipped 17.4px, the two badges disagreed on
	# **2.1% of their pixels** -- and that number is flat from 12px to 32px, so
	# they were the same badge at every size this game will ever draw one. The
	# comment on BURN below still claimed its notch was "what stops it reading as
	# the droplet above at small size". It did not, and nobody could have seen
	# that by looking, because anyone looking already knows which is which.
	#
	# Nothing curved and tapered survives beside a flame at 17 pixels, so bleed
	# stops being curved. One bold diagonal slash: the only diagonal bar in the
	# set, angular where every neighbour is round, and it cannot be notched into
	# a flame.
	CG.Status.BLEED: [
		{"poly": [[-0.60, -0.74], [-0.24, -0.88], [0.64, 0.66], [0.28, 0.80]]},
		# Two drops falling clear of the low end, so it reads as a wound rather
		# than as a stroke of dirt on the plate. Deliberately the first thing to
		# vanish as the badge shrinks: the slash is the read, these are for the
		# hover panel where there is room for them.
		{"dot": [-0.46, 0.46, 0.13]},
		{"dot": [-0.10, 0.80, 0.10]},
	],
	# Flame, asymmetric with one inward notch. **The notch was claimed to be
	# "what stops it reading as the droplet above at small size" and it was not:
	# measured, the two badges shared 98% of their pixels at every size.** BLEED
	# is now a slash, which is what actually separates them. Left as a flame,
	# because a flame is right for burn and it was never the half at fault.
	CG.Status.BURN: [
		{"poly": [
			[0.05, -0.85], [0.45, -0.1], [0.5, 0.3], [0.22, 0.7],
			[-0.22, 0.7], [-0.5, 0.28], [-0.35, -0.15], [-0.18, 0.12], [-0.22, -0.45],
		]},
	],
	# Three bubbles. No outline in common with anything else on the roster,
	# which is worth more here than a skull that turns to mush at 12px.
	CG.Status.POISON: [
		{"dot": [0.0, -0.42, 0.3]},
		{"dot": [-0.4, 0.35, 0.27]},
		{"dot": [0.4, 0.35, 0.27]},
	],
	# Six-spoke asterisk: seeing stars, locked out.
	CG.Status.STUN: [
		{"line": [[-0.75, 0.0], [0.75, 0.0]], "w": 0.2},
		{"line": [[-0.38, -0.65], [0.38, 0.65]], "w": 0.2},
		{"line": [[-0.38, 0.65], [0.38, -0.65]], "w": 0.2},
	],
	# Crosshair. Singled out for attack.
	CG.Status.MARKED: [
		{"arc": [0.0, 0.0, 0.48], "w": 0.18},
		{"line": [[0.0, -0.95], [0.0, -0.62]], "w": 0.18},
		{"line": [[0.0, 0.62], [0.0, 0.95]], "w": 0.18},
		{"line": [[-0.95, 0.0], [-0.62, 0.0]], "w": 0.18},
		{"line": [[0.62, 0.0], [0.95, 0.0]], "w": 0.18},
	],
	# A weight on a handle. Heavy, therefore slow and held -- and unlike HASTE's
	# chevrons in outline rather than merely reversed, so the two cannot be
	# confused when only one of them is on screen. Flat-bottomed and wide, which
	# is the difference between reading as a weight and reading as a bucket.
	CG.Status.SLOWED: [
		{"arc": [0.0, -0.34, 0.28, PI, TAU], "w": 0.16},
		{"poly": [[-0.5, 0.04], [0.5, 0.04], [0.72, 0.82], [-0.72, 0.82]]},
	],
}

## The rim colour, and the only place the good/bad colour channel is decided.
static func rim_color(status: CG.Status) -> Color:
	return Palette.HP_LOW if CG.is_harmful(status) else Palette.HP_FULL

static func plate_points(status: CG.Status) -> Array:
	return PLATE_BAD if CG.is_harmful(status) else PLATE_GOOD

## Where the glyph sits inside the badge, and it is no longer the middle.
##
## **The structural half of the legibility finding.** Measured at the shipped
## 17.4px, two same-category badges disagreed on a mean of 15.9% of their pixels,
## and the most distinct pair in the whole system shared three quarters of its
## pixels. The reason is an allocation: ~84% of a badge went to plate and rim,
## which encode harmful-versus-helpful -- a fact already carried TWICE, by rim
## colour and by plate direction, deliberately, for colourblind safety -- and
## ~16% went to the glyph, which is the only thing not encoded anywhere else.
##
## Only the glyph can separate two badges in the same category, so only the glyph
## is worth pixels. Two changes, both small in the code and both aimed at that:
##
##   - The box grows from 0.70 of the badge to 0.78, and the rim thins from 0.16
##     to 0.12 of the half-extent.
##   - **The box moves off-centre, away from the plate's point.** The plate is a
##     pentagon: its flat side has room and its point does not. Centring the
##     glyph in the bounding box wasted the flat end to keep clear of a point
##     that is only at one end. Harmful plates point down, so their glyph shifts
##     up, and helpful the other way.
##
## Verified rather than asserted: `Tools/BadgeLegibility.tscn` reports the same
## numbers before and after, and the PR states both.
static func glyph_rect(rect: Rect2, status: CG.Status) -> Rect2:
	var side := minf(rect.size.x, rect.size.y)
	var box := side * 0.78
	var centre := rect.get_center()
	var shift := side * 0.08
	centre.y += -shift if CG.is_harmful(status) else shift
	return Rect2(centre - Vector2(box, box) * 0.5, Vector2(box, box))

## The override a dropped-in PNG lives under: `Assets/UI/status/bleed.png`.
## Lower-cased enum name, so it is guessable without reading any code -- the
## same property that makes `Assets/Units/warrior.png` work.
static func art_name(status: CG.Status) -> StringName:
	return StringName("status/%s" % String(CG.Status.keys()[status]).to_lower())

## One badge filling `rect`. Sized for 12-16px squares; larger works and is what
## a pause-hover panel would want. On screen today it is 17.4px: `UnitView`'s
## `STATUS_BADGE_SIZE` of 14 through `DISPLAY_SCALE` and the arena's own scale.
##
## Draws a dropped-in PNG if one exists and the generated badge otherwise. The
## caller never asks which.
##
## `stacks` is how many of the status the unit is carrying. **1 draws exactly
## what this drew before the argument existed**, which is the property that made
## it safe to add here rather than in a second function: every existing call site
## is unchanged without being touched.
static func draw_status(canvas: CanvasItem, status: CG.Status, rect: Rect2, stacks: int = 1) -> void:
	var tex := UIArt.texture_for(art_name(status))
	if tex != null:
		UIArt.draw_fit(canvas, tex, rect)
	else:
		# Plate fill first, then rim, then glyph. The fill is a flat dark plate
		# rather than the team colour: a badge has to read the same on a Warrior
		# and on a Ghoul, or the player learns the colour and not the status.
		var plate := UIArt.glyph_points({"poly": plate_points(status)}, rect)
		var half := minf(rect.size.x, rect.size.y) * 0.5
		UIArt.draw_outlined_polygon(canvas, plate, Palette.HP_BACK, rim_color(status), maxf(1.0, half * 0.12))
		UIArt.draw_glyph(canvas, GLYPHS[status], glyph_rect(rect, status), Palette.TEXT)

	# OUTSIDE BOTH BRANCHES, AND THAT IS THE WHOLE POINT.
	#
	# The count is information; the badge behind it is decoration. If this sat in
	# the generated branch, dropping in `Assets/UI/status/bleed.png` would delete
	# the stack count and the screenshot would look fine -- which is this
	# project's own house rule, learned twice already: a dropped-in border
	# silently deleted the party-card selection ring, and a dropped-in PNG
	# silently deleted the granted-action badge. Both were invisible to the
	# instrument we check art with. A picture may replace decoration and it may
	# not replace information.
	if shows_stack_count(stacks):
		draw_stack_count(canvas, status, rect, stacks)

## Whether a count is drawn at all. One is the ordinary case and gets no
## decoration -- a badge that always carries "1" is noise on eleven statuses that
## cannot stack.
static func shows_stack_count(stacks: int) -> bool:
	return stacks >= 2

## What the tab reads. Capped at two digits because the tab is about ten pixels
## wide on screen and a third digit would not be a number, it would be a smudge.
##
## BLEED "stacks infinitely", so the cap is a real loss and it is the right one:
## the difference between 9 and 20 stacks matters and is kept, the difference
## between 99 and 140 does not fit in ten pixels and is shown as "99+" rather
## than as a wrong number.
static func stack_text(stacks: int) -> String:
	return "99+" if stacks > 99 else str(stacks)

## Where the count tab sits: **on the plate's FLAT edge, never on its point, and
## never wider than the badge.**
##
## Both halves of that were found by rendering it and neither by reading it.
##
## **The point carries information and the first version deleted it.** These
## plates point DOWN when harmful and UP when helpful, and `Assets/UI/README.md`
## tells the player that in as many words: *"Both cues carry the same information
## on purpose: the colour is faster to read, and the direction still works for a
## player who cannot separate red from green."* A tab in the bottom-right corner
## sits exactly on a harmful plate's point and rubs it out, so a bleeding unit
## loses the colourblind-safe half of its read at the moment it has most to say.
## That is this project's house rule -- a picture may replace decoration and it
## may not replace information -- broken by me, in the file the rule is about,
## for the third time. So the tab goes on whichever edge is flat.
##
## **And it must not reach sideways into the next badge.** A row of four is drawn
## with a three pixel gap, and a tab overhanging to the right landed on top of
## the neighbouring status. The tab is now right-ALIGNED rather than
## right-overhanging: it grows upward or downward, never outward, so a row can
## never collide however many digits appear.
##
## Overhanging outward rather than inset, still. Inset would shrink the glyph, so
## a bleeding unit's badge would be harder to identify than everybody else's
## exactly when it matters most.
static func stack_count_rect(status: CG.Status, rect: Rect2, stacks: int) -> Rect2:
	var unit := minf(rect.size.x, rect.size.y)
	var height := unit * 0.58
	# Width from the text that will actually be drawn, not from a per-digit
	# multiplier. The multiplier was written for two characters and "99+" is
	# three, so the plus sign hung outside its own pill.
	var width := minf(rect.size.x, height * (0.62 + 0.46 * float(stack_text(stacks).length())))
	# Harmful plates point down, so their flat edge is the top; helpful plates
	# are the other way up. Straddling the flat edge puts half the tab outside
	# the badge and leaves the point untouched.
	var y := rect.position.y - height * 0.5
	if not CG.is_harmful(status):
		y = rect.position.y + rect.size.y - height * 0.5
	return Rect2(Vector2(rect.position.x + rect.size.x - width, y), Vector2(width, height))

## The tab itself. Split from `draw_status` so the geometry above can be tested
## without a live canvas, which is the same split `build_parts` makes and for the
## same reason: `draw_*` outside `_draw()` logs a wall of errors and asserts
## nothing.
static func draw_stack_count(canvas: CanvasItem, status: CG.Status, rect: Rect2, stacks: int) -> void:
	var tab := stack_count_rect(status, rect, stacks)
	var text := stack_text(stacks)
	# Filled with the rim colour rather than the plate colour: the rim is already
	# the good/bad channel, so the tab inherits the read instead of inventing a
	# third colour, and a red tab on a red-rimmed badge cannot be mistaken for a
	# helpful status.
	var radius := tab.size.y * 0.5
	canvas.draw_rect(Rect2(tab.position + Vector2(radius, 0.0), Vector2(maxf(tab.size.x - radius * 2.0, 0.0), tab.size.y)), rim_color(status))
	canvas.draw_circle(tab.position + Vector2(radius, radius), radius, rim_color(status))
	canvas.draw_circle(tab.position + Vector2(tab.size.x - radius, radius), radius, rim_color(status))
	# Dark text on the bright tab. The plate behind is HP_BACK, so this is the
	# same two colours the badge already uses, swapped.
	var font := ThemeDB.fallback_font
	var size := maxi(7, int(tab.size.y * 0.92))
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := tab.position + Vector2(
		(tab.size.x - text_width) * 0.5,
		(tab.size.y + float(font.get_ascent(size)) - float(font.get_descent(size))) * 0.5)
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.HP_BACK)

## Where a row of badges goes, left to right from `top_left`. Returned rather
## than drawn so the caller decides how many fit and what to do when they do
## not -- that is a layout call and layout is `Scripts/UI`'s.
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
