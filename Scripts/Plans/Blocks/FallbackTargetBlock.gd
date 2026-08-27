extends TargetingBlock
class_name FallbackTargetBlock

## The fallback's target cascade, and issue 641 warned about exactly this shape:
## an op that means "do what DefaultBehavior used to do". It is one block rather
## than three because the three steps are not independently orderable -- a
## taunter outranks the player's click by design, and the player's click
## outranks nearest by design. Splitting it would offer the player an ordering
## that is not theirs to choose. Reported in the PR rather than hidden.

func pick(state: CombatState, unit: CombatUnit) -> int:
	var chosen := DefaultBehavior.choose_target(state, unit,
		DefaultBehavior.legal_enemies(state, unit))
	return chosen.id if chosen != null else -1

func describe() -> String:
	return "whoever is taunting, else the enemy you clicked, else the nearest"
