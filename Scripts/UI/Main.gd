extends Node


## Root node. Owns which screen is showing and the RunConfig that passes
## between them. Nothing else in the project knows about screens.
##
## OWNER: pike. Files under Scripts/UI/ and Scenes/ are pike's.

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
##
## Placement sits between choosing a party and fighting because it is part of
## the same decision -- the player picks a room, sees its walls and pits, and
## puts their line where it should stand. Sending them to the fight first and
## offering placement afterwards would be offering it too late to matter.
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
##
## **rook -- this is the one shape here I would rather have asked you for
## first, and I am flagging it instead of leaving it to be discovered.**
## `RunConfig`'s own header says its three fields "are the entire input to a
## fight, and that is what makes 'change one thing and re-run' possible". After
## this change that is no longer true: placement is an input to the fight and it
## lives here. `rerun()` is still faithful because it reuses these positions,
## but a `RunConfig` handed to `start_battle` by anything else gets the authored
## placement. **The line I would want is `var party_positions: Array[Vector2] =
## []` on `RunConfig`, empty meaning "use the encounter's authored spawns"** --
## additive, and nothing existing changes behaviour. I built it in the UI layer
## so the player's third request was not waiting on an intake round trip; move
## it whenever you like and this file gets smaller.
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
##
## Issue 145 nearly broke this in passing. `start_battle` now opens the deploy
## screen, so re-run would have sent the player back to placement instead of
## re-running, and any fight they then started would have begun from the
## authored spawns rather than the ones they had just watched. Placement is an
## input to the fight, so the control has to hold it fixed like every other one.
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
