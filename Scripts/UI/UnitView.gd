extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")

## One combatant on screen: body, health bar, resource bar, name, tags, and the
## wind-up indicator that says an action is coming.
##
## OWNER: pike.
##
## The wind-up indicator is not decoration. ActionDef.wind_up_ticks exists so a
## fight can be read rather than watched, and that only works if the screen
## shows it.

var unit_id: int = -1

func bind(state: CombatState, id: int) -> void:
	push_error("UnitView.bind is not implemented yet (issue 3, owner pike)")

func sync(state: CombatState) -> void:
	push_error("UnitView.sync is not implemented yet (issue 3, owner pike)")
