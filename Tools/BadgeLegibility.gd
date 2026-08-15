extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const StatusIcons := preload("res://Scripts/Art/StatusIcons.gd")
const UIArt := preload("res://Scripts/Art/UIArt.gd")
const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")
const BattleView := preload("res://Scripts/UI/BattleView.gd")

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

## The shipped size sits in here, and so do the sizes either side of it.
const LADDER := [12.0, 14.0, 17.4, 24.0, 32.0]

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
	if image.get_width() != int(get_viewport_rect().size.x):
		printerr("BadgeLegibility: laid out at %d, captured at %d -- CROPPED." % [
			int(get_viewport_rect().size.x), image.get_width()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	image.save_png(CAPTURE_PATH)
	print("BadgeLegibility: wrote ", CAPTURE_PATH)
	_measure(image)
	get_tree().quit(0)

## THE SIZE THE GAME ACTUALLY DRAWS, asked of the function the real screen uses.
##
## This is also where an instrument defect turned up, and it is the reason this
## section prints three numbers instead of one.
func _report_real_sizes() -> void:
	print("")
	print("HOW BIG IS A STATUS BADGE, REALLY")
	for size in [Vector2(1280.0, 720.0), Vector2(844.0, 390.0)]:
		var layout := BattleView.compute_layout(size)
		var px: float = UnitViewScript.STATUS_BADGE_SIZE * layout["scale"].x
		print("  shipped, at %dx%d: %.1f px  (STATUS_BADGE_SIZE %.1f world x arena scale %.4f)" % [
			int(size.x), int(size.y), px, UnitViewScript.STATUS_BADGE_SIZE, layout["scale"].x])
	# What the row of badges costs, against the unit it is describing. A mark
	# wider than the thing it annotates is the crowding the playtest reported as
	# "a dozen 12px badges layered on top of each other".
	var scale: float = BattleView.compute_layout(Vector2(1280.0, 720.0))["scale"].x
	var badge: float = UnitViewScript.STATUS_BADGE_SIZE * scale
	var gap: float = UnitViewScript.STATUS_BADGE_GAP * scale
	var row: float = float(UnitViewScript.MAX_STATUS_BADGES) * badge + 3.0 * gap
	print("  a full row of %d badges is %.0f px wide at 1280x720" % [
		UnitViewScript.MAX_STATUS_BADGES, row])
	for pair in [["goblin", 11.0], ["ghoul", 16.0], ["the_warden", 22.0]]:
		var across: float = float(pair[1]) * UnitViewScript.DISPLAY_SCALE * scale * 2.0
		print("    vs %-11s %.0f px across  -> the badges are %.1fx the unit" % [
			pair[0], across, row / across])
	print("  the diagnostic harness, Tools/IconsOverlay.gd: 14.0 px, HARDCODED")
	print("  -> the harness every judgement about these badges has been made on")
	print("     draws them ~20%% SMALLER than the game does. Its own comment says")
	print("     it exists to stop them 'silently being drawn bigger than they")
	print("     are'. The intent was right and the number was not derived.")

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
		"17.4 is what the game ships. 14.0 is what the diagnostic harness draws. Neither is a choice anyone made.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	for r in LADDER.size():
		var badge: float = LADDER[r]
		var y := _TOP + float(r) * _ROW
		var note := ""
		if is_equal_approx(badge, 17.4):
			note = "  <- SHIPPED"
		elif is_equal_approx(badge, 14.0):
			note = "  <- the harness"
		_label(Vector2(_MARGIN, y - 12.0), "%.1f px%s" % [badge, note],
			Palette.FONT_SIZE_SMALL, Palette.TEXT if note != "" else Palette.TEXT_DIM)
		for c in _statuses.size():
			var at := Vector2(_MARGIN + 90.0 + float(c) * _COL, y)
			StatusIcons.draw_status(self, _statuses[c], Rect2(at, Vector2(badge, badge)))

## ---------------------------------------------------------------------------
## THE MEASUREMENT

func _measure(image: Image) -> void:
	# Every badge box extracted once per size, then reused for ink and for all
	# 78 pairs. The first version re-read the image per pair and blew the tool
	# budget.
	var boxes := {}
	for r in LADDER.size():
		var badge: float = LADDER[r]
		var y := _TOP + float(r) * _ROW
		var row := []
		for c in _statuses.size():
			row.append(_box(image, Vector2(_MARGIN + 90.0 + float(c) * _COL, y), badge))
		boxes[r] = row

	print("")
	print("INK: how many pixels of a badge carry anything at all")
	for r in LADDER.size():
		var badge: float = LADDER[r]
		var total_ink := 0
		for c in _statuses.size():
			total_ink += _ink_of(boxes[r][c], Palette.ARENA_FLOOR)
		var area := badge * badge
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
