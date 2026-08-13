extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")

## The scrolling record of the fight, in words. One line per CombatEvent worth
## showing.
##
## OWNER: pike.
##
## This is half of how the combat gets judged. "That felt bad" has to be
## traceable to a cause, so a line names the actor, the action, the target, the
## number and the mitigation when there was any. A line reading "Warrior hits
## Rat for 7" is not enough to tell a tuning problem from a targeting problem.

func append_event(state: CombatState, event: CombatEvent) -> void:
	push_error("CombatLogView.append_event is not implemented yet (issue 3, owner pike)")

func clear_log() -> void:
	push_error("CombatLogView.clear_log is not implemented yet (issue 3, owner pike)")
