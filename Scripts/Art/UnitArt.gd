extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const UIArt := preload("res://Scripts/Art/UIArt.gd")

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
## texture drew. That loader is `UIArt.load_png` -- one copy, shared with the
## `Assets/UI` drop-in, which needs precisely the same trick for the same reason.
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
		var tex := UIArt.load_png(candidate)
		_cache[candidate] = tex
		if tex != null:
			return tex
	return null

static func has_art(shape_id: StringName, team: CG.Team) -> bool:
	return texture_for(shape_id, team) != null

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
	canvas.draw_texture_rect(tex, signed_rect(tex, radius, facing_left, center), false)

## The rect `draw` hands to `draw_texture_rect`, signed: `size.x` is negative
## when the sprite is mirrored. Split out of `draw` only so a test can assert
## the arithmetic without a renderer -- the gate is headless and reads back
## nothing, so the alternative was no guard at all.
##
## Issue 241, and the arithmetic is the whole of that bug. **A negative-width
## `Rect2` mirrors the texture in place; it does not move it**: the rect still
## covers `position.x` rightward for `abs(size.x)`. The previous version of
## `draw` was `drawn.x = -drawn.x` *before* building the rect, so
## `center - drawn * 0.5` put the left edge at `center.x + width / 2` and the
## sprite landed **one full drawn width right of the unit**.
##
## Measured, and both halves of that sentence separately:
##
##   - `Rect2(pos.x=200, size.x=+160)` and `Rect2(pos.x=200, size.x=-160)` ink
##     exactly the same columns, 200..359, and the second is the first
##     reversed. So the negation mirrors and does not move.
##   - `Tools/FacingInk.gd`, old code then new, px from the origin:
##     the_warden `+65.5 -> -0.5`, goblin `+32.0 -> -1.0`, warrior
##     `+49.0 -> +2.5`. The displacement is one *drawn width*, not a diameter,
##     which is why the three numbers differ: `warrior.png` is 17x24, so at
##     radius 33 its width is 46.75px and its height is the 66px diameter.
##
## The residual few px are the sprites' own asymmetry, not a leftover error:
## mirroring reflects the opaque pixels about the file's centre, and
## `warrior.png` sits one pixel left of it. Right-facing reads -3.5 and
## left-facing +2.5 about the same -0.5.
##
## What was NOT wrong: the wind-up bar, the hp bar, the badge row, the name.
## `PLAYTEST-FRESH-1`'s "lone cream bar attached to nothing" and issue 241 as
## filed both blamed the chrome; every one of those is centred on the unit and
## always was. Nothing anywhere compensated for the displacement, which is why
## the one-line fix needed no second edit. The targeting lines, impact rings,
## death markers and floaters that spawn at a unit's position were pointing at
## empty floor beside the sprite.
##
## Since #256 `facing_left` follows `CombatUnit.facing`, not the team, so this
## hit **any** unit while it faced left -- usually every enemy, and a player
## pawn any time it turned around.
##
## **Not `draw_set_transform`**, which also works and which `draw`'s own doc
## comment rules out: it silently resets a caller's established transform, and
## `ArtPreview` rendering every real-art unit blank is how that was found.
static func signed_rect(tex: Texture2D, radius: float, facing_left: bool, center: Vector2 = Vector2.ZERO) -> Rect2:
	var size := Vector2(tex.get_width(), tex.get_height())
	var drawn := size * ((radius * 2.0) / maxf(size.x, size.y))
	var rect := Rect2(center - drawn * 0.5, drawn)
	if facing_left:
		rect.size.x = -drawn.x
	return rect

## The rectangle `draw` above actually puts ink in, in the same local space it
## draws into: the texture's **opaque** pixels, not its file dimensions.
##
## Why the distinction is the whole point of this function. `Silhouettes` sizes
## nothing from it, but everything a unit *wears* -- health bar, badge row,
## impact ring, name plate -- is currently sized from the simulation's collision
## radius, which is neither of these. Issue #190. A caller moving off the
## collision radius must not land on the file dimensions instead: pixel art
## carries transparent margin, and `Assets/Units/siege_master.png` is 24x14 with
## only 20x8 of that opaque. Sizing a bar from 24x14 would fix a third of the
## error and look like it had fixed all of it.
##
## `facing_left` is deliberately not a parameter, and the reason is narrower
## than the one written here before. A mirrored sprite has the same *size*, so
## every caller today -- all of them read `size` through
## `UnitView.drawn_half_width` / `drawn_top` / `drawn_bottom` -- is correct
## either way, and a signed width is a bar width waiting to go negative.
##
## Its **position** does move. Mirroring reflects the opaque pixels about the
## file's centre, so art whose ink is off-centre in its file shifts by twice
## that offset: measured in file px, `abomination` +2.5, `cultist` +2.0,
## `goblin_archer` +2.0, `siege_master` +2.0, `warrior` -1.0, `goblin` +0.5,
## the other six exactly zero. At radius 33 the abomination's box is therefore
## ~14px out when it faces left.
##
## No shipped code reads `position.x`. Two measurement tools do -- `BarClutter.
## _body` and `WindUpOffset` -- so their horizontal body edges are off by that
## much for a left-facing off-centre sprite, and by nothing at all for
## `the_warden`, which is symmetric. If shipped code ever needs the position,
## this function takes the parameter; a caller-side fudge would be the third
## instance of the same error.
static func opaque_rect(canvas_radius: float, tex: Texture2D, center: Vector2 = Vector2.ZERO) -> Rect2:
	var size := Vector2(tex.get_width(), tex.get_height())
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2(center, Vector2.ZERO)
	var used := _used_rect(tex)
	# Same scale `draw` uses: longest side of the FILE spans the diameter.
	var scale := (canvas_radius * 2.0) / maxf(size.x, size.y)
	# `used` is in texture pixels from the file's top-left; `draw` centres the
	# whole file on `center`, so shift by half the file before scaling.
	var origin := (Vector2(used.position) - size * 0.5) * scale
	return Rect2(origin + center, Vector2(used.size) * scale)

## The topmost opaque pixel of each texture column, in texture rows from the
## file's top. `INF` for a column with no opaque pixel at all.
##
## Exists so a caller can measure the shape of the **top edge** of the art the
## game really draws, rather than the top edge of polygons it does not. See
## `Silhouettes.top_profile`, which is the only caller and which explains why
## that distinction cost this project a passing test that measured nothing.
##
## Cached beside the textures for the reason `_used_rect` is: `get_image` copies
## the whole image out of the texture.
static var _top_cache: Dictionary = {}

static func column_tops(tex: Texture2D) -> PackedFloat32Array:
	var key := tex.get_instance_id()
	if _top_cache.has(key):
		return _top_cache[key]
	var out := PackedFloat32Array()
	out.resize(tex.get_width())
	out.fill(INF)
	var image := tex.get_image()
	if image != null:
		for x in tex.get_width():
			for y in tex.get_height():
				if image.get_pixel(x, y).a > 0.0:
					out[x] = float(y)
					break
	_top_cache[key] = out
	return out

## `opaque_rect` as a fraction of the footprint the unit is drawn into, per axis.
##
## Computed from the integer pixel counts rather than by scaling and dividing
## back, so a sprite whose art is exactly half its file -- `priest.png` is 12
## opaque columns of 24 -- reports exactly 0.5 instead of 0.49999999999999994.
## A floor test on this value sits right on that boundary today.
static func opaque_fraction(tex: Texture2D) -> Vector2:
	var longest := maxf(tex.get_width(), tex.get_height())
	if longest <= 0.0:
		return Vector2.ZERO
	return Vector2(_used_rect(tex).size) / longest

## Opaque bounds per texture, cached beside the textures themselves. `get_image`
## copies the whole image out of the texture, so calling this per unit per frame
## would be the same mistake `_cache` above exists to avoid, one level down.
static var _used_cache: Dictionary = {}

static func _used_rect(tex: Texture2D) -> Rect2i:
	var key := tex.get_instance_id()
	if _used_cache.has(key):
		return _used_cache[key]
	var image := tex.get_image()
	# A fully transparent image has no used rect at all. Fall back to the whole
	# file rather than to nothing: a zero-size extent would silently collapse
	# every bar sized from it, which is a far more confusing failure than a
	# slightly generous box around art that draws nothing.
	var used := image.get_used_rect() if image != null else Rect2i()
	if used.size.x <= 0 or used.size.y <= 0:
		used = Rect2i(0, 0, tex.get_width(), tex.get_height())
	_used_cache[key] = used
	return used
