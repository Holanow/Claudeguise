extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")

## Real art, if any exists, in place of the placeholder polygons.
##
## MANAGER-OWNED (`Scripts/Art/**`), and built to be thrown away by whoever
## replaces the placeholders. Nobody has to call this: `Silhouettes.draw_unit`
## asks it first and falls back on its own polygons, so every existing call site
## picks up real art without changing a line.
##
## ---------------------------------------------------------------------------
## HOW TO REPLACE THE PLACEHOLDER ART
##
## Drop a PNG into `Assets/Units/` named after the thing it draws:
##
##     Assets/Units/warrior.png
##     Assets/Units/dungeon_grunt.png
##
## That is the whole procedure. No code change, no scene edit, no re-import, no
## registration step. The ids are exactly the class ids and enemy ids already in
## `Scripts/Content/` — `Silhouettes.shape_ids()` prints the full list, and
## `Assets/Units/README.md` has it written out.
##
## If a unit should look different on each side, add `.player` or `.enemy`:
##
##     Assets/Units/warrior.player.png
##     Assets/Units/warrior.enemy.png
##
## The side-specific file wins; otherwise the plain one is used for both.
##
## ---------------------------------------------------------------------------
## WHY IT LOADS IMAGES THE UNUSUAL WAY
##
## `load("res://Assets/Units/warrior.png")` does not work here and it is not
## your fault: Godot only produces a loadable texture for an image after the
## editor has imported it, and the editor does not run on this machine — every
## headless mode hangs, on both the Steam and official 4.7.1 builds. That is
## documented at the top of `Scripts/Core/CG.gd`.
##
## So this reads the file itself with `Image.load()` and builds an
## `ImageTexture`, which was measured working on 2026-08-12: `load()` failed with
## "No loader found", `Image.load()` returned OK at the correct size, and the
## texture drew.
##
## The consequence for you is that **it works whether or not the editor has ever
## imported the file**, which is the property that makes this a drop-in. If the
## editor is ever usable again, nothing here needs to change.

const ART_DIR := "res://Assets/Units"

## Textures live for the process. Loading a PNG per unit per frame would be a
## disaster and the failure would look like the game being slow rather than like
## a caching mistake.
static var _cache: Dictionary = {}

## The texture for a shape, or null when there is no file for it. Null is the
## normal case right now and is not an error: it means "use the placeholder".
static func texture_for(shape_id: StringName, team: CG.Team) -> Texture2D:
	var side := "player" if team == CG.Team.PLAYER else "enemy"
	# Side-specific first, then the shared file.
	for candidate in ["%s/%s.%s.png" % [ART_DIR, shape_id, side], "%s/%s.png" % [ART_DIR, shape_id]]:
		if _cache.has(candidate):
			if _cache[candidate] != null:
				return _cache[candidate]
			continue
		var tex := _load(candidate)
		_cache[candidate] = tex
		if tex != null:
			return tex
	return null

static func has_art(shape_id: StringName, team: CG.Team) -> bool:
	return texture_for(shape_id, team) != null

static func _load(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		push_error("UnitArt: %s exists but could not be read as an image" % path)
		return null
	return ImageTexture.create_from_image(image)

## Draws the texture centred on `center`, scaled so its longest side spans the
## unit's diameter. Aspect ratio is preserved: art that is taller than it is wide
## stays that way rather than being squashed into a square, because a squashed
## sprite reads as a bug and a slightly small one does not.
##
## `center` is a plain additive offset on the drawn rect, the same way
## `Silhouettes.build_parts` adds it to every polygon point -- deliberately NOT
## a `draw_set_transform` call. A caller that has already established its own
## transform before reaching here (`Tools/ArtPreview.gd` does, to lay out a
## grid of shapes in one `_draw()`) would have that transform silently reset
## to identity by a transform call keyed on `center`, which is Vector2.ZERO in
## the overwhelmingly common case -- found exactly that way: every unit with
## real art on disk rendered as a blank circle in ArtPreview's grid while the
## still-polygon units next to them rendered fine, because the polygon path
## never touches the transform and this one used to.
static func draw(canvas: CanvasItem, tex: Texture2D, radius: float, facing_left: bool, center: Vector2 = Vector2.ZERO) -> void:
	var size := Vector2(tex.get_width(), tex.get_height())
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# Real art here is pixel art, drawn small and scaled up a lot -- the
	# project's default filtering is linear (nothing sets otherwise), which
	# blurs it into a smudge at the sizes a pawn is actually drawn. Nearest
	# keeps every pixel a pixel. This only affects this canvas's own texture
	# draws, so it is safe to set unconditionally: the polygon fallback below
	# never draws a texture and is untouched by it.
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var scale := (radius * 2.0) / maxf(size.x, size.y)
	var drawn := size * scale
	if facing_left:
		drawn.x = -drawn.x
	canvas.draw_texture_rect(tex, Rect2(center - drawn * 0.5, drawn), false)

## Every id the game will look for a file under. Used by the test that keeps
## Assets/Units/README.md honest, so the instructions can never drift from the
## content.
static func expected_filenames(shape_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id in shape_ids:
		out.append("%s.png" % id)
	return out
