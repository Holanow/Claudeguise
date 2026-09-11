extends Node

## Issue 919's evidence: a cleared room with its chest standing between the
## doors, a real click on the chest, and the same room afterwards with the
## chest gone. Two panels in one PNG, because `Screenshots/` holds one image
## per issue.
##
##   run.ps1 ChestShot -FixedFps 60

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
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
	if _battle == null or _busy or _done:
		return
	if _panels.is_empty() and _battle.chest_open():
		_busy = true
		_shoot_and_click()

func _shoot_and_click() -> void:
	Engine.time_scale = 1.0
	await _grab()
	var at: Vector2 = _battle._arena.get_global_transform() * FloorChest.rect().get_center()
	print("ChestShot: clicking the chest at %s" % at)
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
	if _battle.chest_open():
		printerr("ChestShot: the chest is still open after a real click on it")
		get_tree().quit(3)
		return
	var run: FloorRun = _battle._floor_run
	var names: Array[String] = []
	for item in run.loot:
		names.append(item.display_name)
	print("ChestShot: the chest held %s" % ", ".join(names))
	for i in 4:
		await get_tree().process_frame
	await _grab()

func _grab() -> void:
	await RenderingServer.frame_post_draw
	_panels.append(get_viewport().get_texture().get_image())
	print("ChestShot: panel %d" % _panels.size())
	_busy = false
	if _panels.size() == 2:
		_write()

func _write() -> void:
	_done = true
	var size := _panels[0].get_size()
	var sheet := Image.create(size.x * _panels.size(), size.y, false, _panels[0].get_format())
	for i in _panels.size():
		sheet.blit_rect(_panels[i], Rect2i(Vector2i.ZERO, size), Vector2i(size.x * i, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/kestrel8_919_chest_clicked.png" % OUT_DIR
	sheet.save_png(path)
	print("ChestShot: wrote %s" % path)
	get_tree().quit(0)
