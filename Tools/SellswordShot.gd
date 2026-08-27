extends Node

## Issue 650. Frames of one `sellsword_crescent` cast in a real BattleView, tiled into
## a strip. The whole point of an authored look is that somebody looks at it.

const OUT := "res://Screenshots/rook_671_sellsword_crescent.png"
const CROP := Vector2i(420, 280)
const COLS := 4
const ZOOM := 2
const FRAMES := 12
const SEED := 7

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in 2:
		out.append(PawnFactory.make_preset_pawn(&"warrior", StringName("g%d" % i), "G%d" % i))
	return out

func _build() -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = &"floor1_sellsword"
	cfg.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, RoomLibrary.get_room(&"floor1_sellsword"))
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

## Steps until sellsword_crescent lands, then returns where it happened.
func _to_the_cast() -> Vector2:
	for _i in 6000:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if e.action_id == &"sellsword_crescent" and e.kind == CG.EventKind.ACTION_START:
				# Crescent winds up for 14 ticks. Capturing from the commit
				# tick films fourteen ticks of a man standing still; the swing
				# is at the END of the wind-up, so skip to just before it.
				for _skip in 13 * 4:
					_frame()
					await get_tree().process_frame
				var v: Node2D = _view._unit_views.get(e.source_id)
				print("VFXShot: sellsword_crescent at tick %d, unit %d" % [e.tick, e.source_id])
				return Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	printerr("VFXShot: no sellsword_crescent in this fight")
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
		var reg := full.get_region(Rect2i(origin, CROP))
		reg.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
		shots.append(reg)
		_frame()
		await get_tree().process_frame
	var rows := int(ceil(float(shots.size()) / float(COLS)))
	var sheet := Image.create(CROP.x * ZOOM * COLS, CROP.y * ZOOM * rows, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP * ZOOM),
			Vector2i((i % COLS) * CROP.x * ZOOM, (i / COLS) * CROP.y * ZOOM))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	sheet.save_png(OUT)
	print("VFXShot: %s" % OUT)
