extends Node

## Issue 729/804's own proof: watch a floor end to end without touching
## anything. Runs a real BattleView through begin_floor at 24x real time,
## screenshots the first frame of every room, and logs one pawn's hp across the
## whole floor so a reviewer can see damage persist without opening the engine.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const OUT_DIR := "res://Screenshots"
const FLOOR_SEED := 3
const TIME_SCALE := 24.0

var _battle: Node = null
var _plan: FloorPlan = null
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
	_plan = FloorGenerator.generate(FLOOR_SEED)
	_log.append("floor seed %d, order: %s" % [FLOOR_SEED, str(FloorWalk.default_order(_plan))])
	for r in _plan.rooms:
		_log.append("  %s at %s, doors: %s" % [r.content_id, r.cell, _door_text(r)])
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.floor_ended.connect(_on_floor_ended)
	_battle.begin_floor(cfg, _plan)

func _process(_delta: float) -> void:
	if _battle == null or _battle.state == null or _shot_pending:
		return
	if _battle._floor_walk.current_id != _room_index:
		_room_index = _battle._floor_walk.current_id
		_shot_pending = true
		_capture()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var room_id: StringName = _plan.room(_battle._floor_walk.current_id).content_id
	var path := "%s/wren_804_floor_room%02d_%s.png" % [OUT_DIR, _battle._floor_walk.cleared_count() + 1, room_id]
	get_viewport().get_texture().get_image().save_png(path)
	var w0: CombatUnit = _battle.state.unit(0)
	_log.append("room %d/%d (%s at %s): unit0 hp %d/%d, alive=%s -- %s" % [
		_battle._floor_walk.cleared_count() + 1, _plan.rooms.size(), room_id,
		_plan.room(_battle._floor_walk.current_id).cell, w0.hp, w0.hp_max, w0.alive, path])
	_shot_pending = false

func _on_floor_ended(victory: bool) -> void:
	_log.append("floor ended, victory=%s" % victory)
	for line in _log:
		print(line)
	get_tree().quit(0)

## The seam the door UI reads, printed so a reviewer can check it against the
## map image without running anything.
func _door_text(room: FloorRoom) -> String:
	var parts: Array[String] = []
	for e in _plan.exits_of(room.id):
		parts.append("%s -> %s" % [
			FloorPlan.direction_name(e["dir"]), _plan.room(int(e["room_id"])).content_id])
	return ", ".join(parts)
