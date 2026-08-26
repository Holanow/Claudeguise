extends AbilityEffect
class_name CleanseEffect

## Strips every harmful status off the target, per `CG.is_harmful`.

func needs_live_target() -> bool:
	return true
