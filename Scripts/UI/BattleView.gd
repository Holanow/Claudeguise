extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")

## Draws one fight and steps it. Reads CombatState and CombatEvent only; it
## never asks the simulation to do anything except step.
##
## OWNER: pike.
##
## The view drives the clock: it calls CombatSim.step() a whole number of times
## per frame and interpolates nothing that affects the outcome. A view that
## stepped by delta would make the fight depend on the frame rate and break the
## re-run.

var state: CombatState = null
var event_cursor: int = 0

func begin(config: RunConfig) -> void:
	push_error("BattleView.begin is not implemented yet (issue 3, owner pike)")

func _process(_delta: float) -> void:
	push_error("BattleView._process is not implemented yet (issue 3, owner pike)")
	set_process(false)

## Drains the events the simulation emitted since the last frame and turns them
## into floating numbers and log lines.
func consume_events() -> void:
	push_error("BattleView.consume_events is not implemented yet (issue 3, owner pike)")
