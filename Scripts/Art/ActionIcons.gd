extends RefCounted
class_name ActionIcons


## One icon per action, shown at the end of a wind-up progress bar so the player
## sees what is coming rather than only that something is.

## The file this icon is drawn from: `Assets/UI/action/warrior_execute.png`. The
## action id, unchanged, for guessability.
static func art_name(action_id: StringName) -> StringName:
	return StringName("action/%s" % action_id)

static func has_glyph(action_id: StringName) -> bool:
	return UIArt.has_art(art_name(action_id))

## One ability icon filling `rect`, sized for roughly 16px squares.
static func draw_action(canvas: CanvasItem, action_id: StringName, _damage_type: CG.DamageType, rect: Rect2) -> void:
	var tex := UIArt.texture_for(art_name(action_id))
	if tex == null:
		canvas.draw_rect(rect, Color.BLACK)
		return
	UIArt.draw_fit(canvas, tex, rect)
