extends Node

## Issue 729's own proof: watch a floor end to end without touching anything.
## Runs a real BattleView through begin_floor at 8x real time, screenshots the
## first frame of every room, and logs one pawn's hp across the whole floor so
## a reviewer can see damage persist without opening the engine.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const OUT_DIR := "res://Screenshots"
const FLOOR_SEED := 3
const TIME_SCALE := 24.0

var _battle: Node = null
var _room_ids: Array[StringName] = []
var _room_index := -1
var _shot_pending := false
var _log := PackedStringArray()

func _ready() -> void:
	Offscreen.hide_window(self)
	Engine.time_scale = TIME_SCALE
	var cfg := RunConfig.new()
	cfg.seed = FLOOR_SEED
	var party: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		party.append(PawnFactory.make_preset_pawn(cid, cid, String(cid)))
	cfg.party = party
	_room_ids = FloorWalk.default_order(FloorGenerator.generate(FLOOR_SEED))
	_log.append("floor seed %d, order: %s" % [FLOOR_SEED, str(_room_ids)])
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.floor_ended.connect(_on_floor_ended)
	_battle.begin_floor(cfg, _room_ids)

func _process(_delta: float) -> void:
	if _battle == null or _battle.state == null or _shot_pending:
		return
	if _battle._floor_index != _room_index:
		_room_index = _battle._floor_index
		_shot_pending = true
		_capture()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var room_id: StringName = _room_ids[_room_index]
	var path := "%s/teal_796_floor_room%02d_%s.png" % [OUT_DIR, _room_index + 1, room_id]
	get_viewport().get_texture().get_image().save_png(path)
	var w0: CombatUnit = _battle.state.unit(0)
	_log.append("room %d/%d (%s): unit0 hp %d/%d, alive=%s -- %s" % [
		_room_index + 1, _room_ids.size(), room_id, w0.hp, w0.hp_max, w0.alive, path])
	_shot_pending = false

func _on_floor_ended(victory: bool) -> void:
	_log.append("floor ended, victory=%s" % victory)
	for line in _log:
		print(line)
	get_tree().quit(0)
