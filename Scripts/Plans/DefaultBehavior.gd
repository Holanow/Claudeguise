extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")

## What a unit does when no plan fires. Every unit has this, including enemies,
## which have no plans at all in this slice.
##
## OWNER: teal.
##
## This is more load-bearing than it looks. A player is not expected to touch
## the plan system until late in the game per README.md, so the default
## behaviour is what most fights actually look like, and it is the thing being
## judged when the question is whether the combat is fun.

static func decide(state: CombatState, unit: CombatUnit) -> Intent:
	push_error("DefaultBehavior.decide is not implemented yet (issue 2, owner teal)")
	return Intent.idle()
