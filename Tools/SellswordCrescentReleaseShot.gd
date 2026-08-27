extends Node

## Issue 690. `sellsword_crescent` at the RELEASE cue (`ACTION_FIRE`, where
## `VFXLayer.Cue.RELEASE` fires and the swing is at full extension) rather than
## mid wind-up, so the arc the fix is proving is actually in frame.

const OUT := "res://Screenshots/linnet_690_sellsword_crescent.png"
const CROP := Vector2i(130, 130)
const ZOOM := 4
const SEED := 11

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	get_viewport().warp_mouse(Vector2(-5000, -5000))
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

## Steps until `sellsword_crescent` fires (`ACTION_FIRE`, the RELEASE cue), and
## returns where its source stood at that instant.
func _to_the_release() -> Vector2:
	for _i in 6000:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if e.action_id == &"sellsword_crescent" and e.kind == CG.EventKind.ACTION_FIRE:
				var v: Node2D = _view._unit_views.get(e.source_id)
				print("SellswordCrescentReleaseShot: RELEASE at tick %d, unit %d" % [e.tick, e.source_id])
				for other in _view.state.units:
					if other.id != e.source_id:
						var ov: Node2D = _view._unit_views.get(other.id)
						if ov != null:
							ov.visible = false
				return Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	printerr("SellswordCrescentReleaseShot: no sellsword_crescent RELEASE in this fight")
	return Vector2.INF

func _run() -> void:
	await _build()
	var at := await _to_the_release()
	if at == Vector2.INF:
		return
	if _view._unit_card != null:
		_view._unit_card.dismiss()
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	# Offset left of centre: the Warrior's own `ShieldWall` "Directional Block"
	# label draws in-world to the target's right and survives hiding the other
	# unit sprites, so centring pulls it into frame.
	var origin := (Vector2i(at) - Vector2i(int(CROP.x * 0.85), CROP.y / 2)).clamp(Vector2i.ZERO, full.get_size() - CROP)
	var reg := full.get_region(Rect2i(origin, CROP))
	reg.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	reg.save_png(OUT)
	print("SellswordCrescentReleaseShot: %s" % OUT)
