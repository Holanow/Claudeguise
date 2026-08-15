extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const SoundBank := preload("res://Scripts/Audio/SoundBank.gd")

## The six placeholder voices, drawn and named.
##
##   godot --path . --resolution 1280x740 res://Tools/SoundSheet.tscn
##
## No --headless. `get_viewport().get_texture()` never populates under --headless
## on this machine; a real window works. Written up in Tools/AttackFXPreview.gd.
##
## **The width must be 1280** and that is not a preference. The project's
## `canvas_items` stretch pins the logical viewport to a design width of 1280, so
## at any other window width the layout is computed in one space and captured in
## another. Run first at 1000x760 and the sheet drew to logical x=1250 into a
## 1000-pixel image, quietly cutting the long waveforms off at the right edge --
## the same trap EquipmentIconSheet.gd records losing a whole column to, hit
## again by someone who had read that comment. The tool now says so if it drifts.
##
## WHY THIS IS A SCENE AND NOT A FEW LINES IN SoundProbe
##
## It was a few lines in SoundProbe, drawing straight into an `Image`. Then I
## looked at the output: six waveforms, no labels, because an `Image` has no way
## to draw text. Six anonymous squiggles is a picture that has replaced
## information rather than decoration, which is the exact trap this project wrote
## down as a house rule after a border deleted a selection ring and a PNG deleted
## a granted-action badge. Nothing in a test could have caught it and I only saw
## it by rendering it, which is now the third time.
##
## WHAT IT CAN AND CANNOT SETTLE
##
## It settles length, envelope and pitch bend, which are three of the four things
## that make these separable. It cannot settle pitch: 440 Hz and 880 Hz look the
## same at this scale, so the number is printed beside each row instead of being
## left to the picture. **And it cannot settle whether they sound good, because I
## cannot hear.** The .wav files next to it are the artifact for whoever can --
## `Tools/SoundProbe.gd` writes them to Screenshots/sound_placeholders/.

const CAPTURE_PATH := "res://Screenshots/sound_placeholders.png"

const _MARGIN := 30.0
const _LABEL_W := 250.0
const _ROW_H := 96.0
const _TOP := 134.0

var _font: Font = null

func _ready() -> void:
	print("SoundSheet: logical viewport is ", get_viewport_rect().size)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	# Says it rather than shipping a silently cropped sheet. A picture missing its
	# right-hand third still looks like a finished picture, which is why this is a
	# printed complaint and not a comment.
	if image.get_width() != int(get_viewport_rect().size.x):
		printerr("SoundSheet: laid out at logical width %d and captured at %d." % [
			int(get_viewport_rect().size.x), image.get_width()])
		printerr("  The right edge of this sheet is CROPPED. Re-run with --resolution 1280x740.")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	var err := image.save_png(CAPTURE_PATH)
	if err != OK:
		printerr("SoundSheet: could not save %s (error %d)" % [CAPTURE_PATH, err])
	else:
		print("SoundSheet: wrote ", CAPTURE_PATH)
	get_tree().quit(0)

func _label(at: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw() -> void:
	_font = ThemeDB.fallback_font
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BACKGROUND)

	_label(Vector2(_MARGIN, 40.0), "Placeholder sounds", Palette.FONT_SIZE_HEADING, Palette.TEXT)
	_label(Vector2(_MARGIN, 66.0),
		"Six synthetic blips. Every one is replaced by dropping a file into Assets/Audio.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	_label(Vector2(_MARGIN, 86.0),
		"All rows share one time axis, so a long sound looks long. Pitch is printed, not drawn:",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	# Said on the picture rather than only in the source. A high row genuinely
	# looks thinner here -- one pixel spans many cycles and the line samples one
	# of them -- and a reader who does not know that reads it as quieter, which
	# it is not. All six peak within 0.19-0.22.
	_label(Vector2(_MARGIN, 106.0),
		"a high-pitched row draws thin because one pixel spans many cycles. All six peak the same.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	var kinds: Array = SoundBank.PLACEHOLDER_VOICES.keys()
	var longest := 0
	for kind in kinds:
		longest = maxi(longest, SoundBank.placeholder_for(kind).data.size() / 2)

	var wave_x := _MARGIN + _LABEL_W
	var wave_w := size.x - wave_x - _MARGIN

	for r in kinds.size():
		var kind = kinds[r]
		var v: Array = SoundBank.PLACEHOLDER_VOICES[kind]
		var data: PackedByteArray = SoundBank.placeholder_for(kind).data
		var count := data.size() / 2
		var mid := _TOP + float(r) * _ROW_H + _ROW_H * 0.5

		# The name is the whole point of this file existing. `event/<name>` is
		# also literally the filename a player drops in, so the label doubles as
		# the instruction rather than needing a legend somewhere else.
		var name := String(CG.EventKind.keys()[kind]).to_lower()
		_label(Vector2(_MARGIN, mid - 4.0), "event/%s" % name, Palette.FONT_SIZE_BODY, Palette.TEXT)
		_label(Vector2(_MARGIN, mid + 16.0),
			"%.0f Hz   %.0f ms   %s" % [v[0], v[1] * 1000.0, _bend(v[3])],
			Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

		draw_line(Vector2(wave_x, mid), Vector2(wave_x + wave_w, mid), Palette.ARENA_EDGE, 1.0)
		var points := PackedVector2Array()
		for x in int(wave_w):
			var s := int(float(x) / wave_w * float(longest))
			if s >= count:
				break
			var amp := float(data.decode_s16(s * 2)) / 32767.0
			# Drawn against a fixed full-scale rather than each row's own peak.
			# Normalising per row would draw the quiet MISS as loud as the rest,
			# and how loud one is relative to the others is information.
			points.append(Vector2(wave_x + float(x), mid - amp * _ROW_H * 0.42 / SoundBank.PLACEHOLDER_GAIN))
		if points.size() > 1:
			draw_polyline(points, Palette.TEAM_PLAYER, 1.0)

func _bend(sweep: float) -> String:
	if sweep > 0.01:
		return "rising"
	if sweep < -0.01:
		return "falling"
	return "flat"
