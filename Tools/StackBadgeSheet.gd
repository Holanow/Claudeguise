extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const StatusIcons := preload("res://Scripts/Art/StatusIcons.gd")
const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")
const BattleView := preload("res://Scripts/UI/BattleView.gd")
const UIArt := preload("res://Scripts/Art/UIArt.gd")

## The BLEED stack count, at the size a fight actually draws a status badge.
##
##   godot --path . --resolution 1280x740 res://Tools/StackBadgeSheet.tscn
##
## No --headless. `get_viewport().get_texture()` never populates under --headless
## on this machine; a real window works.
##
## OWNED BY sable (`Scripts/Art/**`).
##
## THE ONE QUESTION THIS EXISTS TO ANSWER
##
## A status badge is **17.4 pixels** on screen. Whether a digit is legible at
## that size is not something to conclude from reading the code, and it decides
## the whole design: if it is not, the honest answer is pips or "many" rather
## than a number that looks like a number and reads as a smudge.
##
## The player's own bar is that a badge identical at one stack and at nine fails.
## And with damage floaters defaulting off (#136), the badge is where a bleed is
## read at all -- so this has to be unmistakable rather than tasteful.

const CAPTURE_PATH := "res://Screenshots/bleed_stacks.png"

var _font: Font = null
var _true_size := 17.4

func _ready() -> void:
	# Asked of the real screen's own arithmetic rather than typed.
	var layout := BattleView.compute_layout(Vector2(1280.0, 720.0))
	_true_size = UnitViewScript.STATUS_BADGE_SIZE * layout["scale"].x
	print("StackBadgeSheet: a status badge is %.1f px on screen" % _true_size)
	# THE HOUSE RULE, CHECKED IN THE PICTURE RATHER THAN ASSERTED.
	#
	# A real PNG is dropped in for BURN for the length of this render, so the
	# sheet shows a badge whose art came from a file, carrying a count. If the
	# count were drawn inside the generated-badge branch -- which is where it
	# started -- BURN would render as a bare picture with the number gone, and
	# that is invisible to every test we have. Deleted again below, so the tool
	# leaves nothing behind.
	_write_stand_in_art()
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_width() != int(get_viewport_rect().size.x):
		printerr("StackBadgeSheet: laid out at %d, captured at %d -- CROPPED." % [
			int(get_viewport_rect().size.x), image.get_width()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	if image.save_png(CAPTURE_PATH) == OK:
		print("StackBadgeSheet: wrote ", CAPTURE_PATH)
	# A 4x nearest-neighbour blow-up as well: a 17px badge cannot be judged from
	# a screenshot viewed at less than 1:1, and every icon defect this project
	# has found was found at true size or above it.
	var crop := image.get_region(Rect2i(0, 150, int(get_viewport_rect().size.x), 190))
	crop.resize(crop.get_width() * 4, crop.get_height() * 4, Image.INTERPOLATE_NEAREST)
	crop.save_png("res://Screenshots/bleed_stacks_x4.png")
	_remove_stand_in_art()
	get_tree().quit(0)

const _STAND_IN := "res://Assets/UI/status/burn.png"

func _write_stand_in_art() -> void:
	if FileAccess.file_exists(_STAND_IN):
		printerr("StackBadgeSheet: %s already exists; not touching the player's file" % _STAND_IN)
		return
	DirAccess.make_dir_recursive_absolute("res://Assets/UI/status")
	# Deliberately garish and obviously not final, the same way the unit-art
	# drop-in was proved: if this square appears, the file path is live.
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.85, 0.2, 0.75, 1.0))
	image.save_png(_STAND_IN)
	UIArt.clear_cache()

func _remove_stand_in_art() -> void:
	DirAccess.remove_absolute(_STAND_IN)
	UIArt.clear_cache()

func _label(at: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw() -> void:
	_font = ThemeDB.fallback_font
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BACKGROUND)

	_label(Vector2(30.0, 38.0), "BLEED stack count", Palette.FONT_SIZE_HEADING, Palette.TEXT)
	_label(Vector2(30.0, 62.0),
		"\"Bleed should differentiate itself from poison in that it does damage less often but stacks infinitely.\"",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	_label(Vector2(30.0, 82.0),
		"A badge identical at one stack and at nine fails the player's own definition of done.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	# --- the row that decides it: true size --------------------------------
	_label(Vector2(30.0, 128.0),
		"TRUE SIZE, %.1f px, from UnitView.STATUS_BADGE_SIZE through BattleView.compute_layout." % _true_size,
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	var counts := [1, 2, 3, 5, 9, 10, 17, 42, 99, 140]
	var x := 40.0
	for n in counts:
		StatusIcons.draw_status(self, CG.Status.BLEED, Rect2(Vector2(x, 200.0), Vector2(_true_size, _true_size)), n)
		_label(Vector2(x - 2.0, 200.0 + _true_size + 22.0), str(n), Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
		x += 62.0

	# The same row on a unit, in a row of badges, which is where it really sits:
	# a bleeding unit usually carries other statuses too and the count has to
	# survive being one of four.
	_label(Vector2(700.0, 170.0), "In a row of four, as a unit actually carries them:",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	var row := StatusIcons.layout_row(Vector2(700.0, 200.0), 4, _true_size, 3.0)
	var statuses := [CG.Status.BLEED, CG.Status.POISON, CG.Status.SLOWED, CG.Status.SHIELD]
	var stacks := [12, 1, 1, 1]
	for i in 4:
		StatusIcons.draw_status(self, statuses[i], row[i], stacks[i])

	# --- large, so the shape of the tab can be judged ----------------------
	_label(Vector2(30.0, 400.0), "At inspect size, where a hover panel would draw it:",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	var big := 78.0
	x = 40.0
	for n in [1, 2, 9, 10, 99, 140]:
		StatusIcons.draw_status(self, CG.Status.BLEED, Rect2(Vector2(x, 430.0), Vector2(big, big)), n)
		x += big + 40.0

	# --- the house rule, checked in the picture ----------------------------
	# A dropped-in PNG must not delete the count. This draws the same badge with
	# a stand-in "player art" square behind it so the overlay is visible even
	# when nothing has been dropped in.
	_label(Vector2(700.0, 400.0), "Other statuses, one stack. BURN is a dropped-in PNG:",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	x = 700.0
	for s in [CG.Status.BLEED, CG.Status.BURN, CG.Status.POISON, CG.Status.STUN, CG.Status.SHIELD, CG.Status.HASTE]:
		StatusIcons.draw_status(self, s, Rect2(Vector2(x, 430.0), Vector2(big, big)), 1)
		x += big + 16.0

	# The house rule, made visible: the same dropped-in PNG, carrying a count.
	# The magenta square is a file on disk, not a generated badge. If the number
	# is missing from it, art has deleted information and the screenshot is the
	# only place that shows it.
	_label(Vector2(700.0, 570.0), "A dropped-in PNG MUST still carry its count:",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	x = 700.0
	for n in [1, 4, 27]:
		StatusIcons.draw_status(self, CG.Status.BURN, Rect2(Vector2(x, 600.0), Vector2(big, big)), n)
		x += big + 40.0
