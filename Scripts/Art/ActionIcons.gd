extends RefCounted
class_name ActionIcons


## One icon per action, shown at the end of a wind-up progress bar so the player
## sees what is coming rather than only that something is.
##
## MANAGER-OWNED (`Scripts/Art/**`). The bar is `Scripts/UI/UnitView.gd`.
##
## **The icons are PNGs in `Assets/UI/action/`.** They were polygons in code,
## baked to files and the geometry deleted -- player's ruling, 2026-08-19: *"we
## should do basically 0 drawing with code ever"*. The pictures did not change.
## The bake tool went with them: `git log --diff-filter=D -- Tools/BakeGlyphs.gd`.
##
## `Assets/UI/README.md` holds the rules a repaint should keep, and
## `Tests/test_art.gd` measures the one that can be measured: no two of these
## are the same picture, in pixels.

## The file this icon is drawn from: `Assets/UI/action/warrior_execute.png`. The
## action id, unchanged, for guessability.
static func art_name(action_id: StringName) -> StringName:
	return StringName("action/%s" % action_id)

static func has_glyph(action_id: StringName) -> bool:
	return UIArt.has_art(art_name(action_id))

## One ability icon filling `rect`, sized for roughly 16px squares.
##
## `damage_type` is unused now that the colour is painted into the file. It is
## kept because every call site passes what `UnitView` already resolved, and
## dropping it would be a change to files three other sessions have open.
##
## An action with no file draws a black square, by the player's ruling: *"a
## missing sprite can fall back to a black square"*.
static func draw_action(canvas: CanvasItem, action_id: StringName, _damage_type: CG.DamageType, rect: Rect2) -> void:
	var tex := UIArt.texture_for(art_name(action_id))
	if tex == null:
		canvas.draw_rect(rect, Color.BLACK)
		return
	UIArt.draw_fit(canvas, tex, rect)
