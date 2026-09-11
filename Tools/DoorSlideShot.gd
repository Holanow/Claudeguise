extends Node

## Issue 805's evidence: a resolved room with its doors open, a real click on
## one of them, and the screen mid-travel. One PNG, three panels left to right,
## because `Screenshots/` holds one image per issue.
##
##   run.ps1 DoorSlideShot -FixedFps 60

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const AUTOPILOT := preload("res://Tools/FloorAutoPilot.gd")
const OUT_DIR := "user://probe"
const FLOOR_SEED := 3
const TIME_SCALE := 16.0

var _battle: Node = null
var _panels: Array[Image] = []
var _busy := false
var _done := false

func _ready() -> void:
	Offscreen.hide_window(self)
	Engine.time_scale = TIME_SCALE
	var cfg := RunConfig.new()
	cfg.seed = FLOOR_SEED
	var party: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		party.append(PawnFactory.make_preset_pawn(cid, cid, String(cid)))
	cfg.party = party
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin_floor(cfg, FloorGenerator.generate(FLOOR_SEED))

func _process(_delta: float) -> void:
	if _battle == null or _battle.state == null or _busy or _done:
		return
	if _panels.is_empty():
		if _battle.doors_open():
			_busy = true
			_shoot_the_doors()
		return
	# Two frames of the travel: the room being left, then the room arriving.
	if _battle._slide_left < 0.0:
		return
	var travelled: float = 1.0 - _battle._slide_left / BattleView.FLOOR_SLIDE_SECONDS
	if (_panels.size() == 1 and travelled > 0.3) or (_panels.size() == 2 and travelled > 0.72):
		_busy = true
		_grab()

func _shoot_the_doors() -> void:
	Engine.time_scale = 1.0
	await _grab()
	var room := AUTOPILOT.next_door(_battle)
	var at := AUTOPILOT.door_point(_battle, room)
	print("DoorSlideShot: clicking the door to %s at %s" % [
		_battle._floor_walk.plan.room(room).content_id, at])
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		## Issue 904: already viewport space, so the stretch transform must not
		## be applied to it a second time.
		get_viewport().push_input(e, true)
		await get_tree().process_frame
	_busy = false

func _grab() -> void:
	await RenderingServer.frame_post_draw
	_panels.append(get_viewport().get_texture().get_image())
	print("DoorSlideShot: panel %d" % _panels.size())
	_busy = false
	if _panels.size() == 3:
		_write()

func _write() -> void:
	_done = true
	var size := _panels[0].get_size()
	var sheet := Image.create(size.x * _panels.size(), size.y, false, _panels[0].get_format())
	for i in _panels.size():
		sheet.blit_rect(_panels[i], Rect2i(Vector2i.ZERO, size), Vector2i(size.x * i, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/kestrel6_805_doors_and_the_slide.png" % OUT_DIR
	sheet.save_png(path)
	print("DoorSlideShot: wrote %s" % path)
	get_tree().quit(0)
