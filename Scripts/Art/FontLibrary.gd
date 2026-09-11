extends RefCounted
class_name FontLibrary


## The two typographic voices a ledger has: the printed form and the clerk's
## entry. `Assets/Fonts/README.md` says which face is which and why.
const DIR := "res://Assets/Fonts"

const PRINTED_PATH := "%s/EBGaramond/EBGaramond.ttf" % DIR
const ENTRY_PATH := "%s/Spectral/Spectral-Regular.ttf" % DIR
const ENTRY_BOLD_PATH := "%s/Spectral/Spectral-SemiBold.ttf" % DIR

## Engraved headings are wide, not tight. Letterspacing is what makes caps read
## as pre-printed furniture rather than as shouting.
const PRINTED_TRACKING := 2

static var _cache: Dictionary = {}

## The pre-printed voice: titles, column headings, button faces. Caps and
## letterspaced -- set the text in caps yourself, the face is not a small-caps
## family.
static func printed() -> Font:
	return _tracked(&"printed", PRINTED_PATH, PRINTED_TRACKING)

## The written voice: names, figures, the log. Tabular digits.
static func entry() -> Font:
	return _face(ENTRY_PATH)

static func entry_bold() -> Font:
	return _face(ENTRY_BOLD_PATH)

## The imported face at `path`, or null when there is no import to load: an
## export ships the imported resource and not the `.ttf`, so reading the file is
## the fallback for a font dropped in while the game runs, never the first try.
static func _imported(path: String) -> FontFile:
	if not ResourceLoader.exists(path, "FontFile"):
		return null
	return ResourceLoader.load(path, "FontFile") as FontFile

## Null when the file is missing, which is the one case worth saying out loud:
## Godot silently falls back to its own default face and the screen looks
## merely wrong rather than broken.
static func _face(path: String) -> FontFile:
	if _cache.has(path):
		return _cache[path]
	var font := _imported(path)
	if font == null and FileAccess.file_exists(path):
		font = FontFile.new()
		if font.load_dynamic_font(path) != OK:
			push_error("FontLibrary: %s exists but could not be read as a font" % path)
			font = null
	if font == null:
		push_error("FontLibrary: no font at %s" % path)
	else:
		font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		font.hinting = TextServer.HINTING_LIGHT
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	_cache[path] = font
	return font

static func _tracked(key: StringName, path: String, tracking: int) -> Font:
	if _cache.has(key):
		return _cache[key]
	var base := _face(path)
	var out: Font = base
	if base != null:
		var v := FontVariation.new()
		v.base_font = base
		v.spacing_glyph = tracking
		out = v
	_cache[key] = out
	return out
