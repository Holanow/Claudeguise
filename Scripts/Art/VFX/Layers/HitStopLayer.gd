extends VFXLayer
class_name HitStopLayer

## Delegates to BattleView, which owns the freeze and the `hit_stop` toggle.
func play(ctx: Dictionary) -> void:
	ctx["director"].hit_stop()

func describe() -> String:
	return "a hit stop"
