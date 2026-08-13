extends Node

const RunConfig := preload("res://Scripts/Core/RunConfig.gd")

## Root node. Owns which screen is showing and the RunConfig that passes
## between them. Nothing else in the project knows about screens.
##
## OWNER: pike. Files under Scripts/UI/ and Scenes/ are pike's.

const SCENE_PARTY_SELECT := "res://Scenes/PartySelect.tscn"
const SCENE_BATTLE := "res://Scenes/Battle.tscn"

var run_config: RunConfig = null
var _current: Node = null

func _ready() -> void:
	show_party_select()

## The seed round-trips: coming back from a fight re-shows the seed that
## fight actually ran on, rather than a fresh random one on every visit,
## which would make "run the same fight again" a lie the moment a player
## glances away from the screen and back.
func show_party_select() -> void:
	_swap_to(SCENE_PARTY_SELECT, func(screen):
		screen.battle_requested.connect(start_battle)
		if run_config != null:
			screen.prefill_seed(run_config.seed_text())
	)

func start_battle(config: RunConfig) -> void:
	run_config = config
	_swap_to(SCENE_BATTLE, func(screen):
		screen.restart_requested.connect(rerun)
		screen.back_requested.connect(show_party_select)
		screen.begin(config)
	)

## Same party, same encounter, same seed. The comparison control: it is the
## reason the simulation is deterministic and it is the first thing to check
## works, because if it does not, nothing measured on this screen is worth
## anything.
func rerun() -> void:
	if run_config == null:
		push_error("Main.rerun called with no run_config set")
		return
	start_battle(run_config)

func _swap_to(scene_path: String, wire: Callable) -> void:
	if _current != null:
		remove_child(_current)
		_current.queue_free()
		_current = null
	var packed: PackedScene = load(scene_path)
	var screen := packed.instantiate()
	add_child(screen)
	_current = screen
	wire.call(screen)
