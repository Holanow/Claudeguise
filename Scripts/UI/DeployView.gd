extends Control
class_name DeployView

const CanvasScript := preload("res://Scripts/UI/LevelEditorCanvas.gd")

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
var _hint: Label = null
var _encounter_label: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Issue 237. One line instead of three, and the point is not the two lines:
	# `Assets/UI/README.md` promises the player that dropping in
	# `background/deploy.png` (or `background.png` for every screen at once)
	# re-skins this screen, and until this call existed it did nothing at all.
	# With no file present `background_node` returns exactly the ColorRect this
	# replaced, in exactly this colour, so nothing shipped changes.
	add_child(UIArt.background_node(&"deploy", Palette.BACKGROUND))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_top", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_right", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_bottom", int(Palette.SPACE_L))
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(Palette.SPACE_S))
	margin.add_child(column)

	var title := Label.new()
	title.text = "Place your party"
	title.add_theme_font_size_override("font_size", Palette.FONT_SIZE_HEADING)
	title.add_theme_color_override("font_color", Palette.TEXT)
	column.add_child(title)

	_encounter_label = Label.new()
	_encounter_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	_encounter_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(_encounter_label)

	# States the constraint in words as well as drawing it. The shaded band says
	# *where*; only a sentence says *why the pawn stopped moving*, which is the
	# thing a player hits first and cannot deduce from a colour.
	_hint = Label.new()
	_hint.text = "Drag a pawn to move it. The shaded band is as far forward as your party may start, and nobody can stand inside a wall or a pit."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	_hint.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(_hint)

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
	column.add_child(_canvas)
	if not _canvas.is_inside_tree():
		_canvas._ready()

	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", int(Palette.SPACE_M))
	column.add_child(buttons)

	var fight := Button.new()
	fight.text = "Start Fight"
	fight.custom_minimum_size = Vector2(220.0, Palette.TOUCH_TARGET_MIN)
	fight.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	fight.pressed.connect(_on_fight_pressed)
	buttons.add_child(fight)

	# Getting back to where you started has to be one press. Without it the
	# only way to undo a bad placement is to leave the screen and come back,
	# which also throws away the party and the seed.
	var reset := Button.new()
	reset.text = "Reset placement"
	reset.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	reset.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	reset.pressed.connect(reset_placement)
	buttons.add_child(reset)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	back.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	back.pressed.connect(func(): back_requested.emit())
	buttons.add_child(back)

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
