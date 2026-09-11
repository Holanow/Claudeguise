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

## Issue 944: `--skip-chests` walks a cleared room's chest past, which is what
## every walker did before this issue, so the two arms are one tool.
static func _skip_chests() -> bool:
	return OS.get_cmdline_user_args().has("--skip-chests")

var _battle: Node = null
var _plan: FloorPlan = null
var _room_index := -1
var _shot_pending := false
var _log := PackedStringArray()
var _skip := false
var _offer_room := -1
var _chests_opened := 0
var _boss_gear := "never reached the boss"
var _boss_resource := "never reached the boss"

func _ready() -> void:
	Offscreen.hide_window(self)
	Engine.time_scale = TIME_SCALE
	_skip = _skip_chests()
	var cfg := RunConfig.new()
	var seed := _seed()
	cfg.seed = seed
	var party: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		party.append(PawnFactory.make_preset_pawn(cid, cid, String(cid)))
	cfg.party = party
	_plan = FloorGenerator.generate(seed)
	_log.append("floor seed %d, arm %s, order: %s" % [
		seed, "skip-chests" if _skip else "loot", str(FloorWalk.default_order(_plan))])
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
	_note_offer()
	## Issue 944: a player standing in a cleared room with both open takes the
	## chest first, so the walker does too. The skip arm still has to click the
	## boss chest: with the doors shut it is the only exit (#935).
	if _battle.chest_open() and not (_skip and _battle.doors_open()):
		_shot_pending = true
		_take_the_chest()
		return
	if _battle.doors_open():
		_shot_pending = true
		_take_a_door()

## What this room's chest is holding, read once per room in both arms, so the
## report can say whether skipping changes what a later room offers.
func _note_offer() -> void:
	if not _battle.chest_open() or _offer_room == _battle._floor_walk.current_id:
		return
	_offer_room = _battle._floor_walk.current_id
	var ids: Array[String] = []
	for item in _battle._chest_loot:
		ids.append(String(item.id))
	_log.append("  %s chest offers [%s]" % [
		_plan.room(_offer_room).content_id, ", ".join(ids)])

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

## A real click on the chest. The picture is the held boss chest only, which is
## the one room where the chest is the exit rather than a choice beside a door.
func _take_the_chest() -> void:
	var held: bool = not _battle.doors_open()
	if held or _chests_opened == 0:
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [OUT_DIR,
			"wren7_935_boss_chest" if held else "heron7_944_chest_before_the_door"]
		get_viewport().get_texture().get_image().save_png(path)
		_log.append("  chest standing, doors_open=%s -- %s" % [not held, path])
	var before: int = _battle._floor_run.loot.size()
	await _click(AUTOPILOT.chest_point(_battle))
	_chests_opened += 1
	var run: FloorRun = _battle._floor_run
	_log.append("  opened %s's chest: %d item(s), run total %d dropped / %d worn / %d bagged" % [
		_plan.room(_battle._floor_walk.current_id).content_id,
		run.loot.size() - before, run.loot.size(),
		run.loot.size() - run.bag.size(), run.bag.size()])
	_shot_pending = false

## Every slot that has something in it, in party order, by display name so the
## rarity is on the line: the player's question was about affixes.
func _gear_text() -> String:
	var parts: Array[String] = []
	for p in _battle._floor_party:
		var worn: Array[String] = []
		for slot in FloorRun.SLOT_PROPERTY.values():
			var item = p.get(slot)
			if item != null:
				worn.append("%s=%s" % [slot, item.display_name])
		parts.append("%s[%s]" % [p.id, ", ".join(worn)])
	return " ".join(parts)

## Issue 868: every pawn's resource pool as the room opens, because the
## between-room claim is about what a caster walks in with, not its health.
func _resource_text() -> String:
	var parts: Array[String] = []
	for i in _battle._floor_party.size():
		var u: CombatUnit = _battle.state.unit(i)
		parts.append("%s %d/%d" % [_battle._floor_party[i].id, u.resource, u.resource_max])
	return ", ".join(parts)

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
	_log.append("  wearing: %s" % _gear_text())
	_log.append("  resource: %s" % _resource_text())
	if _plan.room(_battle._floor_walk.current_id).type == FloorRoom.Type.BOSS:
		_boss_gear = _gear_text()
		_boss_resource = _resource_text()
	_shot_pending = false

func _on_floor_ended(victory: bool) -> void:
	_log.append("floor ended, victory=%s" % victory)
	var run: FloorRun = _battle._floor_run
	_log.append("SUMMARY seed=%d arm=%s rooms_cleared=%d boss_reached=%s boss_won=%s chests=%d dropped=%d worn=%d bagged=%d" % [
		_seed(), "skip-chests" if _skip else "loot",
		_battle._floor_walk.cleared_count(), _boss_gear != "never reached the boss",
		victory, _chests_opened, run.loot.size(),
		run.loot.size() - run.bag.size(), run.bag.size()])
	_log.append("SUMMARY gear on arrival in the boss room: %s" % _boss_gear)
	_log.append("SUMMARY resource on arrival in the boss room: %s" % _boss_resource)
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
