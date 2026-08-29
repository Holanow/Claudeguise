extends Node

## Issue 748: one winning floor, recorded end to end. Runs the real BattleView
## through `begin_floor` at real speed so the movie writer captures a run a
## viewer could have played, and shoots the first frame of every room beside it.
##
##   run.ps1 -Scene res://Tools/FloorRecord.tscn -FixedFps 60 -WriteMovie <path.avi>

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const OUT_DIR := "res://Screenshots"
const FLOOR_SEED := 36
const PARTY := [&"abomination", &"priest", &"siege_master", &"warrior"]

var _battle: Node = null
var _room_seen := -1
var _shot := 0
var _shot_pending := false
var _held := 0

func _ready() -> void:
	Offscreen.hide_window(self)
	var cfg := RunConfig.new()
	cfg.seed = FLOOR_SEED
	var party: Array[PawnData] = []
	for cid in PARTY:
		party.append(PawnFactory.make_preset_pawn(cid, cid, ClassLibrary.get_class_def(cid).display_name))
	cfg.party = party
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.floor_ended.connect(_on_floor_ended)
	_battle.begin_floor(cfg, FloorGenerator.generate(FLOOR_SEED))

func _process(_delta: float) -> void:
	if _battle == null or _battle.state == null or _shot_pending:
		return
	var walk: FloorWalk = _battle._floor_walk
	if walk != null and walk.current_id != _room_seen:
		_room_seen = walk.current_id
		_shot_pending = true
		_capture(walk)

func _capture(walk: FloorWalk) -> void:
	await RenderingServer.frame_post_draw
	_shot += 1
	var content: StringName = walk.plan.room(walk.current_id).content_id
	var path := "%s/run36_%02d_%s.png" % [OUT_DIR, _shot, content]
	get_viewport().get_texture().get_image().save_png(path)
	print("FloorRecord: room %d (%s) frame %d t=%.2fs -> %s" % [
		_shot, content, Engine.get_frames_drawn(), Engine.get_frames_drawn() / 60.0, path])
	_shot_pending = false

## The end screen is the point of a winning run, so hold on it rather than
## quitting on the frame the Warden dies.
func _on_floor_ended(won: bool) -> void:
	print("FloorRecord: floor ended, won=%s at frame %d t=%.2fs" % [
		won, Engine.get_frames_drawn(), Engine.get_frames_drawn() / 60.0])
	_held = 300
	set_process(false)
	set_process_internal(true)

func _notification(what: int) -> void:
	if what != NOTIFICATION_INTERNAL_PROCESS:
		return
	_held -= 1
	if _held <= 0:
		get_tree().quit(0)
