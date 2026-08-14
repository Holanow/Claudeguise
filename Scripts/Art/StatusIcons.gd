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
## Chosen for shape family first, meaning first: droplet, flame, three dots,
## asterisk, crosshair, weight | shield, wall, shield-and-arc, chevrons, spikes,
## horn. No two share an outline, which is what has to hold at 12px -- the same
## finding as the unit roster, where interior detail vanished and silhouette did
## not.
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
	# Three rising spikes, tallest in the middle. Separate triangles, not one
	# zigzag on a shared baseline: the shared baseline version rendered as a
	# mountain range on the first sheet, because a flat bottom edge is what
	# makes a jagged top edge read as landscape.
	CG.Status.ENRAGE: [
		{"poly": [[-0.78, 0.6], [-0.46, -0.3], [-0.14, 0.6]]},
		{"poly": [[-0.32, 0.7], [0.0, -0.92], [0.32, 0.7]]},
		{"poly": [[0.14, 0.6], [0.46, -0.3], [0.78, 0.6]]},
	],
	# A horn with two sound arcs. Forcing attention, not receiving it.
	CG.Status.TAUNTING: [
		{"poly": [[-0.75, -0.42], [-0.12, -0.75], [-0.12, 0.75], [-0.75, 0.42]]},
		{"arc": [-0.12, 0.0, 0.42, -PI / 2.4, PI / 2.4], "w": 0.16},
		{"arc": [-0.12, 0.0, 0.78, -PI / 2.4, PI / 2.4], "w": 0.16},
	],

	# --- harmful ------------------------------------------------------------
	# Droplet: point up, heavy round bottom.
	CG.Status.BLEED: [
		{"poly": [
			[0.0, -0.8], [0.42, -0.05], [0.42, 0.3], [0.18, 0.65],
			[-0.18, 0.65], [-0.42, 0.3], [-0.42, -0.05],
		]},
	],
	# Flame, asymmetric with one inward notch -- the notch is what stops it
	# reading as the droplet above at small size.
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

## The override a dropped-in PNG lives under: `Assets/UI/status/bleed.png`.
## Lower-cased enum name, so it is guessable without reading any code -- the
## same property that makes `Assets/Units/warrior.png` work.
static func art_name(status: CG.Status) -> StringName:
	return StringName("status/%s" % String(CG.Status.keys()[status]).to_lower())

## One badge filling `rect`. Sized for 12-16px squares; larger works and is what
## a pause-hover panel would want.
##
## Draws a dropped-in PNG if one exists and the generated badge otherwise. The
## caller never asks which.
static func draw_status(canvas: CanvasItem, status: CG.Status, rect: Rect2) -> void:
	var tex := UIArt.texture_for(art_name(status))
	if tex != null:
		UIArt.draw_fit(canvas, tex, rect)
		return
	# Plate fill first, then rim, then glyph. The fill is a flat dark plate
	# rather than the team colour: a badge has to read the same on a Warrior and
	# on a Ghoul, or the player learns the colour and not the status.
	var plate := UIArt.glyph_points({"poly": plate_points(status)}, rect)
	var half := minf(rect.size.x, rect.size.y) * 0.5
	UIArt.draw_outlined_polygon(canvas, plate, Palette.HP_BACK, rim_color(status), maxf(1.0, half * 0.16))
	# The glyph sits in the middle 70% so it never crowds the rim or the point.
	var inner := Rect2(rect.position + rect.size * 0.15, rect.size * 0.7)
	UIArt.draw_glyph(canvas, GLYPHS[status], inner, Palette.TEXT)

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
