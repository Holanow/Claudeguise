extends Node

## Issue 748: one winning floor, recorded end to end. Runs the real BattleView
## through `begin_floor` at real speed so the movie writer captures a run a
## viewer could have played, and shoots the first frame of every room beside it.
##
##   Tools\run.ps1 FloorRecord -FixedFps 60 -TimeoutSeconds 400 -ToolArgs @('--seed','3')
##   ... -WriteMovie <path.avi>    footage as well, and far slower

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const AUTOPILOT := preload("res://Tools/FloorAutoPilot.gd")
const OUT_DIR := "user://probe"
const FLOOR_SEED := 3
const PARTY := [&"abomination", &"priest", &"siege_master", &"warrior"]

## Issue 956: `--seed N`. The old default, 36, loses to the Warden, so an
## unmodified run of a tool that exists to record a won floor recorded a lost one.
static func _seed() -> int:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--seed")
	return int(args[at + 1]) if at >= 0 and at + 1 < args.size() else FLOOR_SEED

var _battle: Node = null
var _floor_seed := FLOOR_SEED
var _room_seen := -1
var _arrivals := 0
var _fights_reached := 0
var _fights_total := 0
var _transit := 0
var _camps := 0
var _shot_pending := false
var _held := 0

func _ready() -> void:
	Offscreen.hide_window(self)
	_floor_seed = _seed()
	var cfg := RunConfig.new()
	cfg.seed = _floor_seed
	var party: Array[PawnData] = []
	for cid in PARTY:
		party.append(PawnFactory.make_preset_pawn(cid, cid, ClassLibrary.get_class_def(cid).display_name))
	cfg.party = party
	var plan := FloorGenerator.generate(_floor_seed)
	## The denominator every count below uses: `FloorWalk.is_fight` excludes the
	## camp, so an 11-room floor is 10 fights and one camp.
	var walk := FloorWalk.new(plan)
	for r in plan.rooms:
		if walk.is_fight(r.id):
			_fights_total += 1
	print("FloorRecord: seed %d, %d rooms, %d fights, camp is room %d" % [
		_floor_seed, plan.rooms.size(), _fights_total, plan.camp_id])
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.floor_ended.connect(_on_floor_ended)
	_battle.begin_floor(cfg, plan)

func _process(_delta: float) -> void:
	if _battle == null or _battle.state == null or _shot_pending:
		return
	var walk: FloorWalk = _battle._floor_walk
	if walk == null or _battle._slide_left >= 0.0:
		return
	if walk.current_id != _room_seen:
		_room_seen = walk.current_id
		_shot_pending = true
		_capture(walk)
		return
	## Issue 944: the chest before the door, because a player standing in a
	## cleared room with both open takes the chest first.
	if _battle.chest_open():
		_battle.open_chest()
	# Issue 805: the floor waits on a door now, and nobody here is a player.
	elif _battle.doors_open():
		_battle.take_door(AUTOPILOT.next_door(_battle))

## Issue 956: an arrival is a room walked into, and most of them are corridor --
## `FloorAutoPilot.next_door` returns one BFS step and `take_door` enters one
## room, so a six-step route to the next fight is six honest arrivals. The old
## line printed the capture counter as a room id, which is why #952 was filed.
func _capture(walk: FloorWalk) -> void:
	await RenderingServer.frame_post_draw
	_arrivals += 1
	var id := walk.current_id
	var content: StringName = walk.plan.room(id).content_id
	var kind := "transit"
	if id == walk.plan.camp_id:
		kind = "camp"
		_camps += 1
	elif walk.is_fight(id) and not walk.is_cleared(id):
		kind = "FIGHT"
		_fights_reached += 1
	else:
		_transit += 1
	var path := "%s/run%d_a%02d_room%02d_%s_%s.png" % [
		OUT_DIR, _floor_seed, _arrivals, id, kind.to_lower(), content]
	get_viewport().get_texture().get_image().save_png(path)
	print("FloorRecord: arrival %d, room %d (%s), %s, fights %d/%d, frame %d t=%.2fs -> %s" % [
		_arrivals, id, content, kind, _fights_reached, _fights_total,
		Engine.get_frames_drawn(), Engine.get_frames_drawn() / 60.0, path])
	_shot_pending = false

## The end screen is the point of a winning run, so hold on it rather than
## quitting on the frame the Warden dies.
func _on_floor_ended(won: bool) -> void:
	print("FloorRecord: floor ended, won=%s at frame %d t=%.2fs" % [
		won, Engine.get_frames_drawn(), Engine.get_frames_drawn() / 60.0])
	print("FloorRecord: seed %d, %d arrivals = %d/%d fights + %d transit + %d camp" % [
		_floor_seed, _arrivals, _fights_reached, _fights_total, _transit, _camps])
	_held = 300
	set_process(false)
	set_process_internal(true)

func _notification(what: int) -> void:
	if what != NOTIFICATION_INTERNAL_PROCESS:
		return
	_held -= 1
	if _held <= 0:
		get_tree().quit(0)
