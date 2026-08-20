extends Node


## Root node. Owns which screen is showing and the RunConfig that passes
## between them. Nothing else in the project knows about screens.

const SCENE_PARTY_SELECT := "res://Scenes/PartySelect.tscn"
const SCENE_BATTLE := "res://Scenes/Battle.tscn"
const SCENE_FLOOR_MAP := "res://Scenes/FloorMap.tscn"
const SCENE_LEVEL_EDITOR := "res://Scenes/LevelEditor.tscn"
const SCENE_DEPLOY := "res://Scenes/Deploy.tscn"

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
		screen.run_requested.connect(start_run)
		screen.level_editor_requested.connect(show_level_editor)
		if run_config != null:
			screen.prefill_seed(run_config.seed_text())
	)

## Issue 19: the level editor is its own screen (not an overlay like
## InspectPanel) because testing a room opens a real BattleView inside it —
## an overlay-on-an-overlay was more state to keep straight than a screen
## swap, and "Back" already means "return to party select" everywhere else.
func show_level_editor() -> void:
	_swap_to(SCENE_LEVEL_EDITOR, func(screen):
		screen.back_requested.connect(show_party_select)
	)

## Issue 145: Start Fight goes to the deploy screen, not straight to the battle.
func start_battle(config: RunConfig) -> void:
	run_config = config
	_swap_to(SCENE_DEPLOY, func(screen):
		screen.back_requested.connect(show_party_select)
		screen.deploy_confirmed.connect(func(positions: Array[Vector2]):
			start_battle_at(config, positions))
		screen.open(config)
	)

## The placement the player chose, carried on this node rather than on
## `RunConfig`.
var _party_positions: Array[Vector2] = []

func start_battle_at(config: RunConfig, positions: Array[Vector2]) -> void:
	run_config = config
	_party_positions = positions
	var encounter = DeployView.encounter_with_placement(
		Registry.get_encounter(config.encounter_id), positions)
	_swap_to(SCENE_BATTLE, func(screen):
		screen.restart_requested.connect(rerun)
		screen.back_requested.connect(show_party_select)
		screen.begin_with_encounter(config, encounter)
	)

## Same party, same encounter, same seed **and same placement**. The comparison
## control: it is the reason the simulation is deterministic and it is the first
## thing to check works, because if it does not, nothing measured on this screen
## is worth anything.
func rerun() -> void:
	if run_config == null:
		push_error("Main.rerun called with no run_config set")
		return
	start_battle_at(run_config, _party_positions)

## Issue 43: a run instead of a single fight. FloorGenerator.generate is
## seeded from the same RunConfig.seed the single-fight path already uses,
## so the seed field means the same thing on both buttons.
func start_run(config: RunConfig) -> void:
	run_config = config
	var plan := FloorGenerator.generate(config.seed)
	var run := FloorRun.new(plan)
	_swap_to(SCENE_FLOOR_MAP, func(screen):
		screen.back_requested.connect(show_party_select)
		screen.run_ended.connect(func(_victory: bool): show_party_select())
		screen.open(run, config.party)
	)

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
