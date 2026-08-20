extends Control
class_name DeployView

const CanvasScript := preload("res://Scripts/UI/LevelEditorCanvas.gd")
const SCENE := "res://Scenes/Deploy.tscn"

## Issue 145: place your party before the fight starts.
##
## OWNER: wren.
##
## **Asked for three times** -- round one note 23, round two note 10, and again
## in round three -- and it kept slipping because it lived as a bullet in a
## notes file rather than as an issue. Nothing here is a new system. Every piece
## already existed and none of them had been put in front of the player:
##
##   - `Encounter.party_spawns` already carries per-pawn positions and
##     `CombatSim` already reads them.
##   - `CG.party_deploy_max_x()` already defines the zone.
##   - `LevelEditorCanvas` already draws that zone, the same arena a fight
##     draws, and the room's terrain.
##
## So this screen is a canvas in `MOVE_PARTY` mode and a write, and the code
## below is mostly wiring rather than mechanism. That is the point.
##
## **Why it is a decision and not a fiddle.** The rooms have walls, pillars,
## hazards and pits, so the terrain has to be visible or the player is guessing.
## And only one class can redirect an enemy while the Warden kills strictly
## nearest-first, which means **who starts nearest currently decides a great
## deal and is chosen by list order, invisibly.** This screen is the direct
## answer to that: the player picks who is closest, and can see what they are
## standing behind.

signal deploy_confirmed(positions: Array[Vector2])
signal back_requested()

var _canvas: Control = null
var _encounter = null
var _party: Array[PawnData] = []
var _authored: Array[Vector2] = []
var _encounter_label: Label = null

## The tree this screen needs lives in `Scenes/Deploy.tscn`; `new()` gives a bare
## Control with none of it. Always build this screen with `create()`.
static func create() -> DeployView:
	return (load(SCENE) as PackedScene).instantiate() as DeployView

## Only what the scene file cannot express. The heading, the hint sentence and
## the three buttons are in `Scenes/Deploy.tscn` and are edited there; their
## margins, font sizes and dim colours are literals in that file rather than
## reads of `Palette`, so editing the scene is not silently undone at runtime.
func _ready() -> void:
	theme = AppTheme.shared()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Issue 237. `Assets/UI/README.md` promises the player that dropping in
	# `background/deploy.png` (or `background.png` for every screen at once)
	# re-skins this screen. With no file present `background_node` returns exactly
	# a ColorRect in `Palette.BACKGROUND`. Built here rather than in the scene
	# because which node it is depends on whether that file exists; moved to index
	# 0 because it has to draw behind the tree the scene already brought.
	var background := UIArt.background_node(&"deploy", Palette.BACKGROUND)
	add_child(background)
	move_child(background, 0)

	_encounter_label = %EncounterLabel

	# `mode` is a plain var, not an @export, so the canvas cannot be a scene node:
	# a scene child's _ready() runs before this one and would build the arena in
	# the wrong mode. It is built here and slotted in above the button row.
	_canvas = Control.new()
	_canvas.set_script(CanvasScript)
	_canvas.mode = CanvasScript.Mode.MOVE_PARTY
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# add_child FIRST, then the manual _ready() only if the engine will not run
	# one -- the order PartySelect already uses for its panels, and the reason
	# matters here more than it does there. `LevelEditorCanvas._ready()` builds
	# its `ArenaFloor` child, so calling it before `add_child` on a screen that
	# IS in a live tree gets it called twice and builds **two** arenas: the real
	# one plus a ghost at a stale layout, drawn over the heading. Visible only
	# on a screenshot; every test passed with the ghost present, because a
	# detached screen never gets the engine's second call.
	%Column.add_child(_canvas)
	%Column.move_child(_canvas, %Buttons.get_index())
	if not _canvas.is_inside_tree():
		_canvas._ready()

	%FightButton.pressed.connect(_on_fight_pressed)
	# Getting back to where you started has to be one press. Without it the
	# only way to undo a bad placement is to leave the screen and come back,
	# which also throws away the party and the seed.
	%ResetButton.pressed.connect(reset_placement)
	%BackButton.pressed.connect(func(): back_requested.emit())

## `encounter` is passed rather than looked up so the level editor's unsaved
## room can use this screen too, exactly as `BattleView.begin_with_encounter`
## does and for the same reason.
func open(cfg: RunConfig, encounter = null) -> void:
	_encounter = encounter if encounter != null else Registry.get_encounter(cfg.encounter_id)
	_party = cfg.party
	if _encounter == null:
		return
	_encounter_label.text = _encounter.display_name if _encounter.display_name != "" else String(_encounter.id)
	_canvas.terrain = _encounter.terrain
	_canvas.enemy_spawns = _enemy_spawns()
	_canvas.party_radius = _party_radius()
	_canvas.party_labels = _labels()
	# `terrain` on the canvas is not the same thing as `terrain` on the
	# `ArenaFloor` that draws it -- the canvas copies it across in `_relayout`.
	# Setting the field alone left the room's walls in the data and off the
	# screen, which is exactly the failure this issue exists to fix, and the
	# terrain test caught it.
	_canvas._relayout()
	_authored = _authored_positions()
	reset_placement()

## The positions the fight would have used with no deploy screen at all, taken
## from `CombatSim.party_spawn_position` rather than reimplemented, so the
## screen opens on the status quo instead of on a second opinion about it.
func _authored_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in _party.size():
		out.append(CombatSim.party_spawn_position(_encounter, i))
	return out

## What the party is facing, in the shape `LevelEditorOverlay` already draws --
## which gives the enemy names for free, and those are the half of the decision
## the issue's four bullets do not mention.
##
## **The room's terrain was called out as the thing that stops placement being a
## guess, and the enemies are the same argument only stronger.** Choosing who
## stands nearest is choosing who meets the front rank first; without the enemy
## line on screen the player is picking a formation against nothing. Two lines,
## because the drawing already existed.
##
## `radius` comes from the same `EnemyDef` the fight builds the unit from, so a
## big enemy reads big here rather than at a placeholder size.
func _enemy_spawns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spawn in _encounter.enemy_spawns:
		var def = Registry.get_enemy(spawn.enemy_id)
		out.append({
			"enemy_id": spawn.enemy_id,
			"position": spawn.position,
			"radius": def.radius if def != null else 22.0,
		})
	return out

func _labels() -> Array[String]:
	var out: Array[String] = []
	for pawn in _party:
		out.append(pawn.display_name)
	return out

## Every pawn draws and grabs at one radius: `CombatUnit.radius`'s default is
## the same for every class, and taking it from the units themselves would make
## the grab target disagree with the fight if that ever stops being true.
func _party_radius() -> float:
	return 22.0

func reset_placement() -> void:
	var fresh: Array[Vector2] = []
	for p in _authored:
		fresh.append(p)
	_canvas.party_spawns = fresh
	_canvas.queue_redraw()
	if _canvas._overlay != null:
		_canvas._overlay.queue_redraw()

func placements() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in _canvas.party_spawns:
		out.append(p)
	return out

func _on_fight_pressed() -> void:
	deploy_confirmed.emit(placements())

## A copy of the room with the player's placement written into it. A copy and
## not a mutation: `Registry`'s encounters are shared, and writing placement
## straight into one would silently change every later fight in the same room --
## including the re-run that exists to be a comparison control.
static func encounter_with_placement(base, positions: Array[Vector2]):
	var out := Encounter.new()
	out.id = base.id
	out.display_name = base.display_name
	out.enemy_spawns = base.enemy_spawns
	out.terrain = base.terrain
	var spawns: Array[Vector2] = []
	for p in positions:
		spawns.append(p)
	out.party_spawns = spawns
	return out
