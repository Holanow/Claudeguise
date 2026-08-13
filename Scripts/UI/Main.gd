extends Node

const RunConfig := preload("res://Scripts/Core/RunConfig.gd")

## Root node. Owns which screen is showing and the RunConfig that passes
## between them. Nothing else in the project knows about screens.
##
## OWNER: pike. Files under Scripts/UI/ and Scenes/ are pike's.

const SCENE_PARTY_SELECT := "res://Scenes/PartySelect.tscn"
const SCENE_BATTLE := "res://Scenes/Battle.tscn"

var run_config: RunConfig = null

func _ready() -> void:
	show_party_select()

func show_party_select() -> void:
	push_error("Main.show_party_select is not implemented yet (issue 3, owner pike)")

func start_battle(config: RunConfig) -> void:
	run_config = config
	push_error("Main.start_battle is not implemented yet (issue 3, owner pike)")

## Same party, same encounter, same seed. The comparison control: it is the
## reason the simulation is deterministic and it is the first thing to check
## works, because if it does not, nothing measured on this screen is worth
## anything.
func rerun() -> void:
	push_error("Main.rerun is not implemented yet (issue 3, owner pike)")
