extends VFXLayer
class_name ScreenShakeLayer

## Delegates to BattleView rather than shaking anything itself, so the player's
## `screen_shake` display toggle keeps deciding whether it happens at all.
@export var pixels: float = 13.0

func play(ctx: Dictionary) -> void:
	ctx["director"].shake(pixels)

func describe() -> String:
	return "a screen shake"
