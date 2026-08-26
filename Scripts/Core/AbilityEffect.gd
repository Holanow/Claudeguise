extends Resource
class_name AbilityEffect

## One thing an action does when it arrives. An action that does three things
## lists three of these; composition is by listing, not by wrapping.

## Whether the sim must settle a death before running this effect. A pull or a
## cleanse on a corpse is not a thing that happens, so `_apply_action_effect`
## runs the death check immediately before the first effect that says yes.
func needs_live_target() -> bool:
	return false
