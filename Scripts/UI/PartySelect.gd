extends Control

const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

## Pick up to four pawns and a seed, then start the fight.
##
## OWNER: pike.
##
## Swapping the party between runs is an acceptance criterion for this slice, so
## this screen is not a placeholder. It generates one pawn per class from
## Registry.all_class_ids() and lets the player choose.

signal battle_requested(config: RunConfig)

func _ready() -> void:
	push_error("PartySelect._ready is not implemented yet (issue 3, owner pike)")

func current_config() -> RunConfig:
	push_error("PartySelect.current_config is not implemented yet (issue 3, owner pike)")
	return RunConfig.new()
