extends Node

## Issue 729/804's own proof: watch a floor end to end. Runs a real BattleView
## through begin_floor at 24x real time, screenshots the first frame of every
## room, and logs one pawn's hp across the whole floor so a reviewer can see
## damage persist without opening the engine.
##
## Issue 805: a floor no longer walks itself, so this pushes a real click on a
## real door -- `Tools/FloorAutoPilot.gd` stands in for the player's choice.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const AUTOPILOT := preload("res://Tools/FloorAutoPilot.gd")
const OUT_DIR := "user://probe"
const FLOOR_SEED := 3
const TIME_SCALE := 24.0

## Issue 935: `--seed N`, because the boss is the room this now has to reach and
## seed 3's party loses to the Warden.
static func _seed() -> int:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--seed")
	return int(args[at + 1]) if at >= 0 and at + 1 < args.size() else FLOOR_SEED

var _battle: Node = null
var _plan: FloorPlan = null
var _room_index := -1
var _shot_pending := false
var _log := PackedStringArray()

func _ready() -> void:
	Offscreen.hide_window(self)
	Engine.time_scale = TIME_SCALE
	var cfg := RunConfig.new()
	var seed := _seed()
	cfg.seed = seed
	var party: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		party.append(PawnFactory.make_preset_pawn(cid, cid, String(cid)))
	cfg.party = party
	_plan = FloorGenerator.generate(seed)
	_log.append("floor seed %d, order: %s" % [seed, str(FloorWalk.default_order(_plan))])
	for r in _plan.rooms:
		_log.append("  %s at %s, doors: %s" % [r.content_id, r.cell, _door_text(r)])
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.floor_ended.connect(_on_floor_ended)
	_battle.begin_floor(cfg, _plan)

func _process(_delta: float) -> void:
	if _battle == null or _battle.state == null or _shot_pending:
		return
	# The screen is still travelling, so the room is only half on it.
	if _battle._slide_left >= 0.0:
		return
	if _battle._floor_walk.current_id != _room_index:
		_room_index = _battle._floor_walk.current_id
		_shot_pending = true
		_capture()
		return
	if _battle.doors_open():
		_shot_pending = true
		_take_a_door()
		return
	## Issue 935: the boss room holds the floor open on its chest, and a click
	## on it is the only way past.
	if _battle.chest_open():
		_shot_pending = true
		_take_the_chest()

## A real `InputEventMouseButton` pair at the door's own viewport position,
## pushed through Godot's picking. Issue 904: `in_local_coords` true, because
## the point is already viewport space.
func _take_a_door() -> void:
	var room := AUTOPILOT.next_door(_battle)
	if room < 0:
		_log.append("no door out of room %d" % _battle._floor_walk.current_id)
		_on_floor_ended(false)
		return
	var at := AUTOPILOT.door_point(_battle, room)
	_log.append("  clicked the door to %s at %s" % [
		_plan.room(room).content_id, at])
	await _click(at)
	_shot_pending = false

## The picture of the cleared boss room with its chest still standing, then the
## click that opens it.
func _take_the_chest() -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/wren7_935_boss_chest.png" % OUT_DIR
	get_viewport().get_texture().get_image().save_png(path)
	var at := AUTOPILOT.chest_point(_battle)
	_log.append("  boss chest holding the floor open, clicked at %s -- %s" % [at, path])
	await _click(at)
	_log.append("  the chest held %d item(s)" % _battle._floor_run.loot.size())
	_shot_pending = false

func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e, true)
		await get_tree().process_frame

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
