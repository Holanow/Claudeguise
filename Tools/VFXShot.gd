extends Node

## Issue 650. Frames of one `geyser_blast` cast in a real BattleView, tiled into
## a strip. The whole point of an authored look is that somebody looks at it.

const OUT := "res://Screenshots/rook_650_geyser_blast.png"
const CROP := Vector2i(560, 300)
const COLS := 4
const FRAMES := 16
const SEED := 7

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in 4:
		out.append(PawnFactory.make_preset_pawn(&"geysermancer", StringName("g%d" % i), "G%d" % i))
	return out

func _build() -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = CG.DEFAULT_ENCOUNTER
	cfg.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER))
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

## Steps until geyser_blast lands, then returns where it happened.
func _to_the_cast() -> Vector2:
	for _i in 6000:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if e.action_id == &"geyser_blast" and e.kind == CG.EventKind.ACTION_START:
				var v: Node2D = _view._unit_views.get(e.source_id)
				print("VFXShot: geyser_blast at tick %d, unit %d" % [e.tick, e.source_id])
				return Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	printerr("VFXShot: no geyser_blast in this fight")
	return Vector2.INF

func _run() -> void:
	await _build()
	var at := await _to_the_cast()
	if at == Vector2.INF:
		return
	var shots: Array[Image] = []
	for _i in FRAMES:
		await RenderingServer.frame_post_draw
		var full := get_viewport().get_texture().get_image()
		var origin := (Vector2i(at) - CROP / 2).clamp(Vector2i.ZERO, full.get_size() - CROP)
		shots.append(full.get_region(Rect2i(origin, CROP)))
		_frame()
		await get_tree().process_frame
	var rows := int(ceil(float(shots.size()) / float(COLS)))
	var sheet := Image.create(CROP.x * COLS, CROP.y * rows, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP),
			Vector2i((i % COLS) * CROP.x, (i / COLS) * CROP.y))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	sheet.save_png(OUT)
	print("VFXShot: %s" % OUT)
