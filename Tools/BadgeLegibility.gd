extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const StatusIcons := preload("res://Scripts/Art/StatusIcons.gd")
const UIArt := preload("res://Scripts/Art/UIArt.gd")
const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")
const BattleView := preload("res://Scripts/UI/BattleView.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")

## How big does a status badge have to be before it means anything?
##
##   godot --path . --resolution 1280x900 res://Tools/BadgeLegibility.tscn
##
## No --headless. `get_viewport().get_texture()` never populates under --headless
## on this machine; a real window works.
##
## OWNED BY sable (`Scripts/Art/**`).
##
## WHY THIS EXISTS
##
## PLAYTEST-FRESH-1, from someone who had never seen the game:
##
##   "~12px pentagon badges (at 4x zoom: a star, a teardrop, a speaker, a heart
##    -- still meaningless, and invisible at 1x)"
##   "The fight screen does not need more information. It needs about a third as
##    much, drawn four times larger."
##
## I cannot answer that by looking, because I already know what every badge
## means and cannot un-know it. **A reader who knows the answer cannot measure
## legibility.** So this measures the thing underneath legibility instead: how
## much two badges physically DIFFER in pixels at a given size. Two badges that
## differ in nine pixels are not telling anyone apart, whatever they depict.
##
## It reports three things and none of them is an opinion:
##
##   1. The size the game actually draws a badge, derived from the real screen's
##      own layout function rather than recomputed here.
##   2. Ink: how many pixels of a badge carry the glyph at all.
##   3. Discrimination: for every PAIR of badges, the fraction of pixels that
##      differ. The worst pair is the one that decides the system, and the
##      within-category pairs are the ones that matter, because harmful-versus
##      -helpful is already carried by rim colour and plate direction.

const CAPTURE_PATH := "res://Screenshots/badge_legibility.png"

## The sizes the game actually draws sit in here, and so do the sizes either
## side of them.
##
## **This ladder used to start at 12.0 and label 17.4 as "SHIPPED", and both
## became false.** Issue #190 made the badge scale with the drawn body, and the
## body is small: measured through `status_badge_size`, every ordinary enemy --
## goblin, archer, cultist, ghoul, rat, stalker -- is pinned to the clamp FLOOR
## at 8.7 px, and the largest pawn reaches 15.9. The size this document was
## arguing about is now the size nothing on the field is drawn at.
##
## 4.7 is the same floor at 844x390. It is on the ladder because that is what a
## phone gets, not because anything could work there.
const LADDER := [4.7, 8.7, 10.4, 15.9, 17.4, 24.0, 32.0]

## Drawn beside a row when it is a size the game really uses, so nobody argues
## about a rung nothing renders at again. Keyed by the ladder value.
const REAL_SIZES := {
	4.7: "every small enemy at 844x390",
	8.7: "<- EVERY ORDINARY ENEMY at 1280x720 (clamp floor)",
	10.4: "<- warrior, geysermancer",
	15.9: "<- siege_master, the largest pawn",
	17.4: "the old pre-#190 size, drawn at nothing now",
}

const _MARGIN := 40.0
const _TOP := 150.0
const _COL := 86.0
const _ROW := 116.0

var _font: Font = null
var _statuses: Array = []

func _ready() -> void:
	for s in CG.Status.values():
		_statuses.append(s)
	_report_real_sizes()
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	image.save_png(CAPTURE_PATH)
	print("BadgeLegibility: wrote ", CAPTURE_PATH)
	_measure(image, float(image.get_width()) / get_viewport_rect().size.x)
	get_tree().quit(0)

## THE SIZE THE GAME ACTUALLY DRAWS, asked of the function the real screen uses.
##
## **This function has now been wrong twice, in opposite directions, and both
## times it looked right.** Keeping the history because the shape of the mistake
## is the same both times and it will be made a third time otherwise:
##
##   1. `Tools/IconsOverlay.gd` hardcoded 14.0 px while the game drew 17.4. Every
##      rendered judgement about these badges, including a playtest's, was made
##      on a picture 20% small. Fixed in #161 and pinned by a test.
##   2. **Then that test pinned the wrong constant.** This file read
##      `UnitViewScript.STATUS_BADGE_SIZE` and called it "the size the game
##      draws". Issue #190 made the badge row scale with the *drawn body*, so
##      that constant became the **maximum of a clamp** that almost nothing
##      reaches. The instrument went from 20% small to substantially large, and
##      the test written to prevent exactly this drift went green throughout,
##      because it compared the harness against the same stale constant.
##
## The lesson, and it is the general one: **a test that pins an instrument to a
## constant only holds while the constant is still the answer.** Ask the
## function, never the constant. `status_badge_size` is the function the screen
## calls, so this asks it, per shape, at each unit's real radius.
func _report_real_sizes() -> void:
	print("")
	print("HOW BIG IS A STATUS BADGE, REALLY")
	# Issue 208: read from the constant, not from a copy of its old value. The
	# floor moved and this line went on printing 10.5 -- a measuring tool that
	# reports a stale number is worse than one that reports nothing.
	print("  floor %.1f world / ceiling %.1f world / cap %d badges" % [
		UnitViewScript.STATUS_BADGE_MIN, UnitViewScript.STATUS_BADGE_SIZE,
		UnitViewScript.MAX_STATUS_BADGES])

	for size in [Vector2(1280.0, 720.0), Vector2(844.0, 390.0)]:
		var layout := BattleView.compute_layout(size)
		var scale: float = layout["scale"].x
		print("")
		print("  at %dx%d (arena scale %.4f)" % [int(size.x), int(size.y), scale])
		print("    %-16s %-8s %-9s %-9s %s" % [
			"unit", "body px", "badge px", "full row", "row / body"])
		for row in _units():
			var radius: float = float(row[1]) * UnitViewScript.DISPLAY_SCALE
			var badge := UnitViewScript.status_badge_size(row[0], row[2], radius) * scale
			var gap := UnitViewScript.STATUS_BADGE_GAP * (badge / (UnitViewScript.STATUS_BADGE_SIZE * scale))
			var body := UnitViewScript.drawn_half_width(row[0], row[2], radius) * 2.0 * scale
			# Issue 208: the gap count was hardcoded at 3, which is right for a
			# row of four and wrong for every other cap. There is one fewer gap
			# than there are slots.
			var slots := float(UnitViewScript.MAX_STATUS_BADGES)
			var full := slots * badge + (slots - 1.0) * gap
			print("    %-16s %-8.1f %-9.1f %-9.1f %.1fx" % [
				row[0], body, badge, full, full / maxf(body, 0.001)])

## Every unit the game can put on a field, with the radius the content gives it.
## Read from the registry rather than typed in here: the last version of this
## carried three hardcoded radii, which is a second copy of a number that lives
## somewhere else and is therefore a number that goes stale silently.
func _units() -> Array:
	var out: Array = []
	# Pawns have no per-class radius: they all take `CombatUnit`'s default, which
	# is read off a real instance rather than copied as a literal.
	var pawn_radius: float = CombatUnit.new().radius
	for cid in Registry.all_class_ids():
		out.append([cid, pawn_radius, CG.Team.PLAYER])
	for eid in Registry.all_enemy_ids():
		out.append([eid, Registry.get_enemy(eid).radius, CG.Team.ENEMY])
	return out

func _label(at: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw() -> void:
	_font = ThemeDB.fallback_font
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BACKGROUND)
	# Drawn on the ARENA FLOOR colour, not the page background: a badge in a
	# fight sits on the floor, and contrast against the wrong ground is the
	# classic way a legibility check flatters itself.
	draw_rect(Rect2(Vector2(_MARGIN - 12.0, _TOP - 40.0),
		Vector2(size.x - _MARGIN * 2.0 + 24.0, float(LADDER.size()) * _ROW + 40.0)), Palette.ARENA_FLOOR)

	_label(Vector2(_MARGIN, 44.0), "How big does a status badge have to be?",
		Palette.FONT_SIZE_HEADING, Palette.TEXT)
	_label(Vector2(_MARGIN, 70.0),
		"PLAYTEST-FRESH-1: \"~12px pentagon badges ... still meaningless, and invisible at 1x\".",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	_label(Vector2(_MARGIN, 90.0),
		"Every row is the same 13 badges. Drawn on the arena floor colour, because that is what they sit on.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	_label(Vector2(_MARGIN, 110.0),
		"Since #190 the badge scales with the DRAWN BODY. Every ordinary enemy sits on the clamp floor at 8.7 px.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	for r in LADDER.size():
		var badge: float = LADDER[r]
		var y := _TOP + float(r) * _ROW
		var note := ""
		for key in REAL_SIZES:
			if is_equal_approx(badge, float(key)):
				note = "  " + str(REAL_SIZES[key])
				break
		_label(Vector2(_MARGIN, y - 12.0), "%.1f px%s" % [badge, note],
			Palette.FONT_SIZE_SMALL, Palette.TEXT if note != "" else Palette.TEXT_DIM)
		for c in _statuses.size():
			var at := Vector2(_MARGIN + 90.0 + float(c) * _COL, y)
			StatusIcons.draw_status(self, _statuses[c], Rect2(at, Vector2(badge, badge)))

## ---------------------------------------------------------------------------
## THE MEASUREMENT

## `capture_scale` is image pixels per layout unit, and it is not always 1.
##
## **The third instrument defect in this file, and the worst-behaved.** The
## project runs `stretch/mode="canvas_items"` with a 1280 base width, so a window
## opened at any other width draws the whole sheet SCALED. `_draw` and `_measure`
## then agreed with each other perfectly and both disagreed with the image: every
## box was read from coordinates the badges were no longer at, and the tool
## reported **0.0% ink and 0.0% discrimination for every badge at every size**.
##
## That failure was at least loud. The dangerous version is a scale near 1, where
## the boxes land slightly off-centre and the numbers stay plausible.
##
## So this no longer assumes the capture is in layout space -- it converts. The
## tool is now correct at any resolution instead of only at 1280 wide, which is
## the property the previous two fixes here both lacked.
func _measure(image: Image, capture_scale: float) -> void:
	if not is_equal_approx(capture_scale, 1.0):
		print("")
		print("  (captured at %.3fx layout scale -- boxes converted to image space)" % capture_scale)
	# Every badge box extracted once per size, then reused for ink and for all
	# 78 pairs. The first version re-read the image per pair and blew the tool
	# budget.
	var boxes := {}
	for r in LADDER.size():
		var badge: float = LADDER[r] * capture_scale
		var y := (_TOP + float(r) * _ROW) * capture_scale
		var row := []
		for c in _statuses.size():
			row.append(_box(image, Vector2((_MARGIN + 90.0 + float(c) * _COL) * capture_scale, y), badge))
		boxes[r] = row

	print("")
	print("INK: how many pixels of a badge carry anything at all")
	for r in LADDER.size():
		var badge: float = LADDER[r]
		var total_ink := 0
		for c in _statuses.size():
			total_ink += _ink_of(boxes[r][c], Palette.ARENA_FLOOR)
		# Ink is counted in IMAGE pixels, so the area it is a fraction of has to
		# be the box's image-space area too. Dividing image-space ink by
		# layout-space area is how a covered badge reports 120%.
		var area := badge * capture_scale * badge * capture_scale
		print("  %5.1f px badge: %4.0f px of box, %4.0f px of ink on average (%.0f%% covered)" % [
			badge, area, float(total_ink) / float(_statuses.size()),
			100.0 * float(total_ink) / float(_statuses.size()) / area])

	print("")
	print("DISCRIMINATION: the fraction of pixels two badges DISAGREE on.")
	print("  Rim colour and plate direction already separate harmful from helpful,")
	print("  so the pairs that decide the system are the ones INSIDE a category --")
	print("  there the glyph is the only thing carrying the difference.")
	for r in LADDER.size():
		var badge: float = LADDER[r]
		var worst_any := 1.0
		var worst_any_pair := ""
		var worst_same := 1.0
		var worst_same_pair := ""
		for a in _statuses.size():
			for b in range(a + 1, _statuses.size()):
				var d := _diff_of(boxes[r][a], boxes[r][b])
				var name_pair := "%s/%s" % [
					String(CG.Status.keys()[_statuses[a]]).to_lower(),
					String(CG.Status.keys()[_statuses[b]]).to_lower()]
				if d < worst_any:
					worst_any = d
					worst_any_pair = name_pair
				if CG.is_harmful(_statuses[a]) == CG.is_harmful(_statuses[b]) and d < worst_same:
					worst_same = d
					worst_same_pair = name_pair
		print("  %5.1f px: closest pair overall %4.1f%% (%s) | closest SAME-CATEGORY %4.1f%% (%s)" % [
			badge, worst_any * 100.0, worst_any_pair, worst_same * 100.0, worst_same_pair])

	# The worst pair alone would let me over-generalise from one outlier, so the
	# whole distribution at the shipped size goes in the record too.
	print("")
	print("EVERY SAME-CATEGORY PAIR AT THE SHIPPED 17.4 px, closest first")
	var shipped := LADDER.find(17.4)
	var pairs := []
	var sum := 0.0
	for a in _statuses.size():
		for b in range(a + 1, _statuses.size()):
			if CG.is_harmful(_statuses[a]) != CG.is_harmful(_statuses[b]):
				continue
			var d := _diff_of(boxes[shipped][a], boxes[shipped][b])
			sum += d
			pairs.append([d, "%s/%s" % [
				String(CG.Status.keys()[_statuses[a]]).to_lower(),
				String(CG.Status.keys()[_statuses[b]]).to_lower()]])
	pairs.sort_custom(func(x, y): return x[0] < y[0])
	for i in mini(10, pairs.size()):
		print("    %5.1f%%  %s" % [pairs[i][0] * 100.0, pairs[i][1]])
	print("    ...")
	print("    %5.1f%%  %s  (the most distinct pair)" % [pairs[-1][0] * 100.0, pairs[-1][1]])
	print("    mean across %d same-category pairs: %.1f%%" % [pairs.size(), sum / float(pairs.size()) * 100.0])

	print("")
	print("STROKE WIDTHS AT THE SHIPPED SIZE")
	# A glyph sits in the middle 70% of the badge, so its own half-extent is what
	# strokes scale against. UIArt._stroke clamps at 1.0 px, and a clamped stroke
	# is the system saying it has run out of room: below that the glyph stops
	# shrinking and starts fusing.
	var inner_half := 17.4 * 0.7 * 0.5
	var clamped := 0
	var counted := 0
	for s in _statuses:
		for part in StatusIcons.GLYPHS[s]:
			if not (part.has("line") or part.has("arc")):
				continue
			counted += 1
			if float(part.get("w", 0.18)) * inner_half <= 1.0:
				clamped += 1
	print("  %d of %d stroked parts are at or below the 1.0 px clamp in UIArt._stroke." % [clamped, counted])
	print("  A clamped stroke means the glyph has stopped scaling down and started fusing.")

## Pulls one badge box out as raw bytes, once. `get_pixel` in a nested loop over
## every pair at every size took longer than the five minute tool budget and had
## to be killed -- 78 pairs x 5 sizes x a thousand pixels each, through a Variant
## call per pixel. Extracting once and comparing bytes is the same measurement.
func _box(image: Image, at: Vector2, size: float) -> PackedByteArray:
	return image.get_region(Rect2i(int(at.x), int(at.y), int(size), int(size))).get_data()

func _ink_of(box: PackedByteArray, ground: Color) -> int:
	var gr := int(ground.r * 255.0)
	var gg := int(ground.g * 255.0)
	var gb := int(ground.b * 255.0)
	var n := 0
	var i := 0
	while i < box.size():
		if absi(box[i] - gr) + absi(box[i + 1] - gg) + absi(box[i + 2] - gb) > 30:
			n += 1
		i += 4
	return n

## Fraction of pixels on which two badge boxes disagree.
func _diff_of(a: PackedByteArray, b: PackedByteArray) -> float:
	var differing := 0
	var total := 0
	var i := 0
	while i < a.size() and i < b.size():
		total += 1
		if absi(a[i] - b[i]) + absi(a[i + 1] - b[i + 1]) + absi(a[i + 2] - b[i + 2]) > 45:
			differing += 1
		i += 4
	return float(differing) / maxf(1.0, float(total))
