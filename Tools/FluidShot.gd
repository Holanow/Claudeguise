extends Node

## Issue 760: a settled pool of water and a pool of blood, filmed as a strip of
## frames rather than one still, because a still cannot judge motion (#707,
## #749). Run it once before the shader and once after with the same label
## pair, and the two strips are the comparison.
##
##   Tools\run.ps1 FluidShot -ToolArgs label=before

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")

## Rendered frames to save. ~0.75 s apart at 60 fps, so a slow surface has
## moved visibly between neighbours.
const CAPTURE_AT := [30, 75, 120, 165]

## A pawn stands in each pool: the legibility question is whether a body over
## a shaded fluid still reads, and only a body over one can answer it.
const WATER_AT := Vector2(-170.0, -40.0)
const BLOOD_AT := Vector2(-170.0, 90.0)

@export var label: String = "before"

var _view: Node2D = null
var _frames := 0
var _saved := 0

func _ready() -> void:
	if not Offscreen.hide_window(self):
		return
	_read_args()
	if not _build():
		get_tree().quit(2)
		return
	RenderingServer.frame_post_draw.connect(_maybe_capture)

func _process(_delta: float) -> void:
	if _view == null:
		return
	_frames += 1
	_view._process(CG.TICK_SECONDS / 4.0)

func _maybe_capture() -> void:
	if not CAPTURE_AT.has(_frames):
		return
	var path := "user://probe/kestrel2_760_fluid_%s_f%d.png" % [label, _frames]
	get_viewport().get_texture().get_image().save_png(path)
	print("FluidShot: ", path)
	_saved += 1
	if _saved >= CAPTURE_AT.size():
		get_tree().quit(0)

func _build() -> bool:
	var pawns: Array[PawnData] = []
	for cid in [&"warrior", &"geysermancer"]:
		pawns.append(PawnFactory.make_starter_pawn(cid, cid, String(cid)))
	var cfg := RunConfig.new()
	cfg.party = pawns
	cfg.seed = 0x2A
	var e := RoomData.new()
	e.id = &"fluid_shot"
	e.display_name = "Fluids"
	e.party_spawns = [WATER_AT, BLOOD_AT]
	e.enemy_spawns = [{"enemy_id": &"goblin_archer", "position": Vector2(280.0, 0.0)}]
	_view = BATTLE_SCENE.instantiate()
	add_child(_view)
	_view.begin_with_encounter(cfg, e)
	_view.set_process(false)
	_paint()
	return true

## Stamped straight onto the live grid rather than fought for: nothing in the
## game paints a big settled pool of either fluid on demand, and this shot is
## about how one looks, not about how it got there.
func _paint() -> void:
	var grid: TerrainGrid = _view.state.grid
	grid.stamp_circle(TerrainGrid.Layer.EFFECTS, WATER_AT, 95.0, _cell(Terrain.Kind.WATER))
	grid.stamp_circle(TerrainGrid.Layer.EFFECTS, Vector2(60.0, -140.0), 70.0, _cell(Terrain.Kind.WATER))
	grid.stamp_circle(TerrainGrid.Layer.EFFECTS, BLOOD_AT, 85.0, _cell(Terrain.Kind.BLOOD))
	grid.stamp_circle(TerrainGrid.Layer.EFFECTS, Vector2(120.0, 150.0), 60.0, _cell(Terrain.Kind.BLOOD))
	_view._arena.queue_redraw()

func _cell(kind: Terrain.Kind) -> TerrainGrid.Cell:
	var c := TerrainGrid.Cell.new()
	c.kind = kind
	return c

func _read_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		var split := arg.find("=")
		if split > 0 and arg.substr(0, split) == "label":
			label = arg.substr(split + 1)
